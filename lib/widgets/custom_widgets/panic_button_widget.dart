import 'package:flutter/material.dart';
import 'package:safestep/panic_screen.dart';


class PanicButtonWidget extends StatefulWidget {
  const PanicButtonWidget({super.key});

  @override
  State<PanicButtonWidget> createState() => _PanicButtonWidgetState();
}

class _PanicButtonWidgetState extends State<PanicButtonWidget> {
  bool _buttonPressed = false;

  void _handlePanicButtonPress() {
    // Perform navigation to TenSecondPanicScreen
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TenSecondPanicScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _buttonPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _buttonPressed = false;
        });
        _handlePanicButtonPress();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _buttonPressed
                      ? [Color(0xFF8F5FE8), Color(0xFF6C63FF)] // pressed: deeper purple
                      : [Color(0xFFB37DF6), Color(0xFF8F5FE8)], // unpressed: lighter purple
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.25),
                    spreadRadius: 5,
                    blurRadius: 8,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.notifications_on_rounded,
                  size: 55,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Panic',
            style: TextStyle(
                fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
