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
  Future<void>? _initializeControllerFuture;

  List<CameraDescription>? cameras;
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();

    _initCamera();

    // Popup panduan setelah UI siap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showGuidePopup();
      }
    });
  }

  @override
  void dispose() {
    if (_initializeControllerFuture != null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      cameras = await availableCameras();

      // Gunakan kamera yang dikirim dari HomePage jika tersedia
      if (cameras != null && cameras!.isNotEmpty) {
        selectedCameraIndex = cameras!.indexWhere(
          (camera) => camera.name == widget.camera.name,
        );

        if (selectedCameraIndex < 0) {
          selectedCameraIndex = 0;
        }
      }

      _controller = CameraController(
        cameras![selectedCameraIndex],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller.initialize();

      await _initializeControllerFuture;

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Error inisialisasi kamera: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (cameras == null || cameras!.length < 2) return;

    selectedCameraIndex = (selectedCameraIndex + 1) % cameras!.length;

    await _controller.dispose();

    _controller = CameraController(
      cameras![selectedCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller.initialize();

    await _initializeControllerFuture;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _takePicture() async {
    try {
      if (_initializeControllerFuture == null) return;

      await _initializeControllerFuture;

      final image = await _controller.takePicture();

      if (!mounted) return;

      Navigator.pop(context, File(image.path));
    } catch (e) {
      print("Error mengambil gambar: $e");
    }
  }

  // Popup panduan
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
    // Jika kamera belum selesai diinisialisasi
    if (_initializeControllerFuture == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasError == false) {
            return Stack(
              children: [
                // Camera Preview
                Positioned.fill(child: CameraPreview(_controller)),

                // Frame wajah
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

                // Tombol back
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

                // Tombol ganti kamera
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

                // Tombol capture
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
              ],
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error kamera: ${snapshot.error}",
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
