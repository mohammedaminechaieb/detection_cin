import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class OpenCvTestScreen extends StatefulWidget {
  const OpenCvTestScreen({super.key});

  @override
  State<OpenCvTestScreen> createState() => _OpenCvTestScreenState();
}

class _OpenCvTestScreenState extends State<OpenCvTestScreen> {
  String _result = "En attente...";

  @override
  void initState() {
    super.initState();
    _testOpenCv();
  }

  void _testOpenCv() {
    try {
      final mat = cv.Mat.zeros(100, 100, cv.MatType.CV_8UC3);
      setState(() {
        _result = "OpenCV fonctionne. Mat créé : ${mat.rows}x${mat.cols}";
      });
      mat.dispose();
    } catch (e) {
      setState(() {
        _result = "Erreur OpenCV : $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(_result)),
    );
  }
}