import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ResultPage extends StatelessWidget {
  final File image;
  final String hasil;
  final Uint8List? heatmap;
  const ResultPage({
    super.key,
    required this.image,
    required this.hasil,
    this.heatmap, //
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Hasil Deteksi"), centerTitle: true),
      body: SingleChildScrollView(
        // 🔥 supaya tidak overflow
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Gambar asli
              const Text(
                "Gambar Asli",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Image.file(image, height: 250),

              const SizedBox(height: 20),

              // Hasil prediksi
              Text(
                hasil,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 30),

              //  HEATMAP
              if (heatmap != null) ...[
                const Text(
                  "Visualisasi Grad-CAM",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                Image.memory(heatmap!), //
              ] else ...[
                const Text("Heatmap tidak tersedia"),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
