import 'package:flutter/material.dart';

class GraficsScreen extends StatefulWidget {
  const GraficsScreen({super.key});

  @override
  State<GraficsScreen> createState() => _GraficsScreenState();
}

class _GraficsScreenState extends State<GraficsScreen> {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Gráficos'));
  }
}
