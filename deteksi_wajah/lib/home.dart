import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'result_page.dart';

import 'camera_page.dart';
import 'package:camera/camera.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  File? _image;

  Uint8List? heatmapImage;
  String hasilPrediksi = "";

  // ================= CAMERA =================
  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    final File? image = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraPage(camera: firstCamera)),
    );

    if (image != null) {
      setState(() {
        _image = image;
      });

      await getHeatmapFromFlask(_image!);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultPage(
            image: _image!,
            hasil: hasilPrediksi,
            heatmap: heatmapImage,
          ),
        ),
      );
    }
  }

  // ================= FLASK API (FIXED) =================
  Future<void> getHeatmapFromFlask(File image) async {
    try {
      var uri = Uri.parse("http://10.182.205.24:5000/predict");
      var request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        var res = await response.stream.bytesToString();

        print("Response Flask: $res");

        var data = jsonDecode(res);

        // ✅ VALIDASI AMAN
        if (data is Map &&
            data.containsKey('heatmap') &&
            data.containsKey('label')) {
          String base64Str = data['heatmap'].toString();

          // remove prefix kalau ada
          if (base64Str.contains(',')) {
            base64Str = base64Str.split(',').last;
          }

          if (!mounted) return;

          setState(() {
            heatmapImage = base64Decode(base64Str);
            hasilPrediksi = data['label'].toString();
          });
        } else {
          print("❌ Format JSON tidak sesuai");
        }
      } else {
        print("❌ Status error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error Flask: $e");
    }
  }

  // ================= GALERI =================
  Future<void> _openGallery() async {
    // Popup konfirmasi sebelum membuka galeri
    final isConfirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Panduan Pemilihan Foto Galeri"),
            content: const Text(
              "• Foto wajah berada di tengah dan terlihat jelas\n"
              "• Foto wajah tidak ditutupi rambut\n"
              "• Foto wajah memiliki pencahayaan yang bagus\n"
              "• Jangan blur\n"
              "• Hindari foto yang memiliki bayangan di wajah",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Batal"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Lanjut"),
              ),
            ],
          ),
        ) ??
        false;

    if (!isConfirmed) return;

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );

    // Jika user tidak memilih gambar
    if (image == null) return;

    // Simpan gambar ke variabel _image
    setState(() {
      _image = File(image.path);

      // Reset hasil sebelumnya
      heatmapImage = null;
      hasilPrediksi = "";
    });

    // Kirim gambar ke Flask API untuk proses deteksi
    await getHeatmapFromFlask(_image!);

    // Pastikan widget masih aktif
    if (!mounted) return;

    // Jika berhasil mendapatkan hasil, tampilkan ke halaman hasil
    if (hasilPrediksi.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultPage(
            image: _image!,
            hasil: hasilPrediksi,
            heatmap: heatmapImage,
          ),
        ),
      );
    } else {
      // Jika deteksi gagal
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gagal mendeteksi gambar dari galeri.")),
      );
    }
  }

  // ================= DIALOG =================
  void _showDetail(String title, String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
          ],
        );
      },
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Deteksi Kesehatan Kulit"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("About Aplikasi"),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.info, color: Colors.blue),
                            title: const Text("Deskripsi"),
                            onTap: () {
                              Navigator.pop(context);
                              _showDetail(
                                "Deskripsi",
                                "Aplikasi deteksi kesehatan kulit berbasis CNN MobileNetV2.",
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.star,
                              color: Colors.orange,
                            ),
                            title: const Text("Fitur"),
                            onTap: () {
                              Navigator.pop(context);
                              _showDetail(
                                "Fitur",
                                "Deteksi dari kamera/galeri + heatmap Grad-CAM.",
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.memory,
                              color: Colors.green,
                            ),
                            title: const Text("Teknologi"),
                            onTap: () {
                              Navigator.pop(context);
                              _showDetail(
                                "Teknologi",
                                "Flutter + Flask API + CNN MobileNetV2 + Grad-CAM.",
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.person,
                              color: Colors.purple,
                            ),
                            title: const Text("Developer"),
                            onTap: () {
                              Navigator.pop(context);
                              _showDetail("Developer", "Lediyana Gansa");
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/11.png', height: 220),

              const SizedBox(height: 20),

              const Text(
                "Selamat Datang!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                "Gunakan kamera atau galeri untuk analisa kulit wajah.",
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              ElevatedButton.icon(
                onPressed: _openCamera,
                icon: const Icon(Icons.camera_alt, color: Colors.blue),
                label: const Text("Kamera"),
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _openGallery,
                icon: const Icon(Icons.photo, color: Colors.blue),
                label: const Text("Galeri"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
