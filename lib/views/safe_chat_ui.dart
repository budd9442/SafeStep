import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// UI-only widgets for SafeChatView: session selector, chat bubbles, input bar, app bar, background.
/// All logic/state is handled in safe_chat_view.dart (controller).

class SafeChatUI {
  static Widget buildAppBar(String botNickname, VoidCallback onSettings) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF8F5FE8), Color(0xFFB9A6F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.15),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white,
              child: Icon(Icons.shield_rounded, color: Color(0xFF8F5FE8), size: 28),
            ),
          ).animate().fade(duration: 400.ms).scale(duration: 400.ms),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(botNickname,
                  key: ValueKey(botNickname),
                  style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
              ),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.shade400,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)],
                    ),
                  ).animate().scaleXY(begin: 0.7, end: 1.0, duration: 600.ms),
                  const SizedBox(width: 4),
                  Text('Online',
                      style: GoogleFonts.lato(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          tooltip: 'Options',
          onPressed: onSettings,
        ).animate().fade(duration: 400.ms).slideX(begin: 0.3, end: 0),
      ],
    );
  }

  static Widget buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8F5FE8), Color(0xFFE9E4F6), Color(0xFFD6D0F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  static Widget buildMessageBubble(Map<String, dynamic> msg, bool isUser, Animation<double> animation, bool showRisk, List<Map<String, dynamic>> messages) {
    final rawTime = msg['timestamp'];
    final DateTime time = rawTime is DateTime
        ? rawTime
        : (rawTime is Timestamp ? rawTime.toDate() : DateTime.now());
    final timeStr = DateFormat('h:mm a').format(time);
    final isBot = msg['role'] == 'ai';
    final isLast = msg == messages.last;
    return SizeTransition(
      sizeFactor: isLast ? animation : kAlwaysCompleteAnimation,
      axisAlignment: 0.0,
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 2),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Icon(Icons.shield_rounded, color: Color(0xFF8F5FE8), size: 20),
              ).animate().fade(duration: isLast ? 350.ms : 0.ms).scale(duration: isLast ? 350.ms : 0.ms),
            ),
          Flexible(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF8F5FE8) : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg['content'] ?? '',
                    style: GoogleFonts.lato(
                      color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ).animate().fade(duration: isLast ? 350.ms : 0.ms).slideX(begin: isUser ? 0.2 : -0.2, end: 0, duration: isLast ? 350.ms : 0.ms),
                  if (showRisk && msg['role'] == 'ai' && msg['risk_analysis'] != null && (msg['risk_analysis'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isUser 
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isUser 
                              ? Colors.white.withOpacity(0.3)
                              : const Color(0xFFFFEAA7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: isUser ? Colors.white70 : const Color(0xFF856404),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              msg['risk_analysis'],
                              style: GoogleFonts.lato(
                                fontSize: 12,
                                color: isUser ? Colors.white70 : const Color(0xFF856404),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // Display error information if there's an error
                  if (msg['role'] == 'ai' && msg['error_code'] != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isUser 
                            ? Colors.red.withOpacity(0.2)
                            : const Color(0xFFF8D7DA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isUser 
                              ? Colors.red.withOpacity(0.3)
                              : const Color(0xFFF5C6CB),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 16,
                                color: isUser ? Colors.red[300] : const Color(0xFF721C24),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Error: ${msg['error_code']}',
                                style: GoogleFonts.lato(
                                  fontSize: 12,
                                  color: isUser ? Colors.red[300] : const Color(0xFF721C24),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (msg['help'] != null && (msg['help'] as String).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              msg['help'],
                              style: GoogleFonts.lato(
                                fontSize: 11,
                                color: isUser ? Colors.red[200] : const Color(0xFF721C24),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: GoogleFonts.lato(
                      color: isUser ? Colors.white70 : Colors.black54,
                      fontSize: 11,
                    ),
                  ).animate().fade(duration: isLast ? 350.ms : 0.ms, delay: isLast ? 100.ms : 0.ms),
                ],
              ),
            ).animate().fade(duration: isLast ? 350.ms : 0.ms).slideY(begin: 0.2, end: 0, duration: isLast ? 350.ms : 0.ms),
          ),
        ],
      ),
    );
  }

  static Widget buildInputBar(TextEditingController controller, bool loading, VoidCallback onSend) {
    return StatefulBuilder(
      builder: (context, setState) {
        controller.addListener(() {
          setState(() {});
        });
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined, color: Color(0xFF8F5FE8)),
                onPressed: () {}, // TODO: Emoji picker
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  style: GoogleFonts.lato(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file, color: Color(0xFF8F5FE8)),
                onPressed: () {}, // TODO: Media picker
              ),
              const SizedBox(width: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: loading
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8F5FE8)),
                      )
                    : IconButton(
                        key: ValueKey(controller.text.isNotEmpty),
                        icon: const Icon(Icons.send, color: Color(0xFF8F5FE8)),
                        onPressed: controller.text.trim().isEmpty ? null : onSend,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget buildSessionSelector({
    required BuildContext context,
    required bool loadingChats,
    required List<Map<String, dynamic>> chatSessions,
    required VoidCallback onNewChat,
    required void Function(String chatId) onSelectChat,
  }) {
    if (loadingChats) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF8F5FE8)),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text('SafeChat', style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Color(0xFF8F5FE8))),
          centerTitle: true,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8F5FE8), Color(0xFFE9E4F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 24, spreadRadius: 4)],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, color: Color(0xFF8F5FE8), size: 32),
                    const SizedBox(width: 10),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('New Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF8F5FE8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        textStyle: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 15),
                        elevation: 0,
                      ),
                      onPressed: onNewChat,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: chatSessions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, color: Colors.grey[300], size: 60),
                              const SizedBox(height: 12),
                              Text('No chats yet', style: GoogleFonts.lato(fontSize: 18, color: Colors.black45)),
                              const SizedBox(height: 6),
                              Text('Tap "New Chat" to start a conversation', style: GoogleFonts.lato(fontSize: 15, color: Colors.black38)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: chatSessions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final chat = chatSessions[i];
                            final created = (chat['createdAt'] is Timestamp)
                                ? (chat['createdAt'] as Timestamp).toDate()
                                : DateTime.now();
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => onSelectChat(chat['id'] as String),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                    border: Border.all(color: const Color(0xFF8F5FE8).withOpacity(0.08)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Color(0xFF8F5FE8).withOpacity(0.13),
                                        child: Icon(Icons.chat_bubble, color: Color(0xFF8F5FE8)),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Chat ${chatSessions.length - i}', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 17)),
                                            const SizedBox(height: 2),
                                            Text(DateFormat('MMM d, yyyy  h:mm a').format(created), style: GoogleFonts.lato(fontSize: 13, color: Colors.black54)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF8F5FE8)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
