from flask import Flask, request, jsonify
import tensorflow as tf
import numpy as np
import cv2
import base64

app = Flask(__name__)

model = tf.keras.models.load_model(
    "model_mobilenetv2_kulit.keras",
    compile=False
)

labels = ["Berminyak", "Flek Hitam", "Jerawat", "Kering-Kusam", "Normal"]

# ================= HAAR CASCADE =================
# Digunakan untuk mendeteksi wajah agar background tidak ikut diproses
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

    # Jika gradient None, isi dengan nol
    if grads is None:
        grads = tf.zeros_like(conv_outputs)

    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))
    conv_outputs = conv_outputs[0]

    heatmap = conv_outputs @ pooled_grads[..., tf.newaxis]
    heatmap = tf.squeeze(heatmap)

    # Konversi ke numpy dan normalisasi
    heatmap = heatmap.numpy()
    heatmap = np.maximum(heatmap, 0)
    heatmap = heatmap / (np.max(heatmap) + 1e-8)

    return heatmap


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

        # ================= FACE DETECTION (HAAR CASCADE) =================
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

        faces = face_cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(100, 100)
        )

        # Jika wajah ditemukan, crop wajah
        if len(faces) > 0:
            # Ambil wajah terbesar
            x, y, w, h = max(faces, key=lambda f: f[2] * f[3])

            # Tambahkan margin 10%
            margin_x = int(w * 0.1)
            margin_y = int(h * 0.1)

            x1 = max(0, x - margin_x)
            y1 = max(0, y - margin_y)
            x2 = min(original.shape[1], x + w + margin_x)
            y2 = min(original.shape[0], y + h + margin_y)

            face = original[y1:y2, x1:x2]

            # Gunakan area wajah untuk prediksi dan heatmap
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

        # Resize heatmap ke ukuran wajah/gambar
        heatmap = cv2.resize(
            heatmap,
            (original.shape[1], original.shape[0]),
            interpolation=cv2.INTER_CUBIC
        )

        # Konversi ke uint8
        heatmap = np.uint8(255 * heatmap)

        # Smooth
        heatmap = cv2.GaussianBlur(heatmap, (25, 25), 0)

        # Color map
        heatmap = cv2.applyColorMap(
            heatmap,
            cv2.COLORMAP_JET
        )

        # Overlay heatmap dengan wajah
        superimposed_img = cv2.addWeighted(
            original,
            0.7,
            heatmap,
            0.3,
            0
        )

        # Encode ke base64
        _, buffer = cv2.imencode(".jpg", superimposed_img)
        img_base64 = base64.b64encode(buffer).decode("utf-8")

        # Response JSON
        return jsonify({
            "kelas": result,
            "label": labels[result],
            "confidence": confidence,
            "heatmap": img_base64
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