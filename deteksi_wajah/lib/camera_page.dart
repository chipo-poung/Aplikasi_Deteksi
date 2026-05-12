import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';

class CameraPage extends StatefulWidget {
  final CameraDescription camera;

  const CameraPage({super.key, required this.camera});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  List<CameraDescription>? cameras;
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();

    _initCamera(); //  ganti dari controller manual

    // ✅ Popup setelah UI siap (TIDAK ERROR)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showGuidePopup();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();

    _controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _controller.initialize();
    setState(() {});
  }

  Future<void> _switchCamera() async {
    if (cameras == null || cameras!.length < 2) return;

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;

    await _controller.dispose();

    _controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _controller.initialize();

    setState(() {});
  }

  Future<void> _takePicture() async {
    await _initializeControllerFuture;
    final image = await _controller.takePicture();

    Navigator.pop(context, File(image.path));
  }

  // ✅ Popup panduan
  void _showGuidePopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Panduan Pengambilan Gambar"),
          content: const Text(
            "• Posisikan wajah di tengah kotak\n"
            "• Pastikan pencahayaan cukup\n"
            "• Pastikan rambut tidak menutupi wajah\n"
            "• Jangan blur\n"
            "• Hindari bayangan di wajah",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                // 📸 Camera Preview
                Positioned.fill(child: CameraPreview(_controller)),

                // 🔥 Frame wajah (biar user tau posisi)
                Center(
                  child: Container(
                    width: 250,
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),

                // 🔙 Tombol back
                Positioned(
                  top: 40,
                  left: 20,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),

                Positioned(
                  top: 40,
                  right: 20,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(
                        Icons.flip_camera_android,
                        color: Colors.white,
                      ),
                      onPressed: _switchCamera,
                    ),
                  ),
                ),

                // 📸 CAPTURE
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.camera,
                            color: Colors.white,
                            size: 35,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ], // ✅ tutup Stack
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ), // ✅ tutup FutureBuilder
    ); // ✅ tutup Scaffold
  }
} // ✅ tutup class
