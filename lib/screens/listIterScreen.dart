import 'package:flutter/material.dart';

class ListIterScreen extends StatefulWidget {
  const ListIterScreen({super.key});

  @override
  State<ListIterScreen> createState() => _ListIterScreenState();
}

class _ListIterScreenState extends State<ListIterScreen> {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Lista Iter'));
  }
}
