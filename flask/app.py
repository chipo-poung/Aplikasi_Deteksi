from flask import Flask, request, jsonify
import tensorflow as tf
import numpy as np
import cv2
import base64

app = Flask(__name__)

# untuk cek flask berjalan dalam browser
@app.route("/")
def home():
    return jsonify({
        "status": "success",
        "message": "Flask API Deteksi Kondisi Kulit Wajah berjalan dengan baik",
        "endpoint": "/predict"
    })

# ================= LOAD MODEL =================
model = tf.keras.models.load_model(
    "model_mobilenetv2_kulit.keras",
    compile=False
)

labels = ["Berminyak", "Flek Hitam", "Jerawat", "Kering-Kusam", "Normal"]

# ================= HAAR CASCADE =================
face_cascade = cv2.CascadeClassifier(
    "haarcascade_frontalface_default.xml"
)

# ================= GRAD-CAM =================
def make_gradcam_heatmap(img_array, model, last_conv_layer_name):
    grad_model = tf.keras.models.Model(
        [model.inputs],
        [model.get_layer(last_conv_layer_name).output, model.output]
    )

    with tf.GradientTape() as tape:
        conv_outputs, predictions = grad_model(img_array)
        tape.watch(conv_outputs)

        class_idx = tf.argmax(predictions[0])
        loss = predictions[:, class_idx]

    grads = tape.gradient(loss, conv_outputs)

    if grads is None:
        grads = tf.zeros_like(conv_outputs)

    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    conv_outputs = conv_outputs[0]

    heatmap = conv_outputs @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)

    heatmap = heatmap.numpy()
    heatmap = np.maximum(heatmap, 0)
    heatmap = heatmap / (np.max(heatmap) + 1e-8)

    return heatmap


# ================= HEATMAP TO BOUNDING BOX =================
def heatmap_to_bbox(heatmap, original_image):
    """
    Mengubah heatmap (0-1) menjadi bounding box.
    Langkah:
    1. Resize heatmap
    2. Konversi ke uint8
    3. Gaussian blur
    4. Thresholding
    5. findContours()
    6. boundingRect()
    """

    # Resize heatmap ke ukuran gambar asli
    h, w = original_image.shape[:2]
    heatmap_resized = cv2.resize(
        heatmap,
        (w, h),
        interpolation=cv2.INTER_CUBIC
    )

    # Konversi ke 0-255
    heatmap_uint8 = np.uint8(255 * heatmap_resized)

    # Smooth agar kontur lebih stabil
    heatmap_uint8 = cv2.GaussianBlur(
        heatmap_uint8,
        (25, 25),
        0
    )

    # Thresholding (60%)
    _, thresh = cv2.threshold(
        heatmap_uint8,
        int(0.6 * 255),
        255,
        cv2.THRESH_BINARY
    )

    # Cari kontur
    contours, _ = cv2.findContours(
        thresh,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE
    )

    # Jika tidak ada kontur
    if not contours:
        return None

    # Ambil kontur terbesar
    largest_contour = max(
        contours,
        key=cv2.contourArea
    )

    # Abaikan kontur kecil
    if cv2.contourArea(largest_contour) < 100:
        return None

    # Bounding rectangle
    x, y, w_box, h_box = cv2.boundingRect(
        largest_contour
    )

    return (x, y, w_box, h_box)


# ================= API =================
@app.route("/predict", methods=["POST"])
def predict():
    try:
        # Validasi upload
        if "image" not in request.files:
            return jsonify({"error": "No image uploaded"}), 400

        file = request.files["image"]

        # Decode gambar
        img = cv2.imdecode(
            np.frombuffer(file.read(), np.uint8),
            cv2.IMREAD_COLOR
        )

        if img is None:
            return jsonify({"error": "Invalid image"}), 400

        # Simpan gambar asli
        original = img.copy()

        # ================= FACE DETECTION =================
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        faces = face_cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(100, 100)
        )

        if len(faces) > 0:
            # Ambil wajah terbesar
            x, y, w, h = max(faces, key=lambda f: f[2] * f[3])

            # Margin 10%
            margin_x = int(w * 0.1)
            margin_y = int(h * 0.1)

            x1 = max(0, x - margin_x)
            y1 = max(0, y - margin_y)
            x2 = min(original.shape[1], x + w + margin_x)
            y2 = min(original.shape[0], y + h + margin_y)

            face = original[y1:y2, x1:x2]

            # Gunakan hanya wajah
            original = face.copy()
            img = face.copy()

            print("Wajah terdeteksi dan di-crop.")
        else:
            print("Wajah tidak terdeteksi, menggunakan gambar asli.")

        # ================= PREPROCESSING =================
        img = cv2.resize(img, (224, 224))
        img = img.astype(np.float32) / 255.0
        img_array = np.expand_dims(img, axis=0)

        # ================= PREDICTION =================
        pred = model.predict(img_array, verbose=0)
        result = int(np.argmax(pred))
        confidence = float(np.max(pred))

        # ================= CARI LAYER CONV TERAKHIR =================
        last_conv_layer = None
        for layer in reversed(model.layers):
            if isinstance(layer, tf.keras.layers.Conv2D):
                last_conv_layer = layer.name
                break

        if last_conv_layer is None:
            return jsonify({"error": "Conv layer not found"}), 500

        print("GradCAM Layer:", last_conv_layer)

        # ================= GRAD-CAM =================
        heatmap = make_gradcam_heatmap(
            img_array,
            model,
            last_conv_layer
        )

        if heatmap is None:
            return jsonify({"error": "Heatmap generation failed"}), 500

        heatmap = np.nan_to_num(heatmap)

        # ================= BOUNDING BOX DARI HEATMAP =================
        bbox = heatmap_to_bbox(heatmap, original)

        # ================= VISUALISASI HEATMAP =================
        heatmap_resized = cv2.resize(
            heatmap,
            (original.shape[1], original.shape[0]),
            interpolation=cv2.INTER_CUBIC
        )

        heatmap_uint8 = np.uint8(255 * heatmap_resized)
        heatmap_uint8 = cv2.GaussianBlur(
            heatmap_uint8,
            (25, 25),
            0
        )

        heatmap_color = cv2.applyColorMap(
            heatmap_uint8,
            cv2.COLORMAP_JET
        )

        # Overlay heatmap dengan wajah
        superimposed_img = cv2.addWeighted(
            original,
            0.7,
            heatmap_color,
            0.3,
            0
        )

        # ================= GAMBAR BOUNDING BOX =================
        bbox_json = None

        if bbox is not None:
            x, y, w_box, h_box = bbox

            cv2.rectangle(
                superimposed_img,
                (x, y),
                (x + w_box, y + h_box),
                (0, 255, 0),
                2
            )

            bbox_json = {
                "x": int(x),
                "y": int(y),
                "w": int(w_box),
                "h": int(h_box)
            }

        # ================= ENCODE BASE64 =================
        _, buffer = cv2.imencode(".jpg", superimposed_img)
        img_base64 = base64.b64encode(buffer).decode("utf-8")

        # ================= RESPONSE JSON =================
        return jsonify({
            "kelas": result,
            "label": labels[result],
            "confidence": confidence,
            "heatmap": img_base64,
            "bbox": bbox_json
        })

    except Exception as e:
        print("FLASK ERROR:", e)
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True,
        use_reloader=False
    )