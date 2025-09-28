import 'package:flutter/material.dart';
import 'package:safestep/home_screen.dart';

class OnboardingPageContent extends StatelessWidget {
  final String imagePath;
  final String title;
  final String subtitle;
  final Widget bottomButton;
  final bool isCurrentPage;

  const OnboardingPageContent({
    super.key,
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.bottomButton,
    required this.isCurrentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top gradient background
        // Top full-width image with optional gradient overlay
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover, // Makes the image cover the area
                ),
              ),
              // Optional: Gradient overlay on top of the image
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    
                  ),
                ),
              ),
            ],
          ),
        ),


        // Bottom curved container
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedOpacity(
            opacity: isCurrentPage ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 600),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(0, isCurrentPage ? 0 : 50, 0),
              height: 350,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(36),
                  topRight: Radius.circular(36),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF764ba2),
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 28),
                  bottomButton,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback? onAuthSuccess;

  const OnboardingScreen({
    super.key,
    required this.phoneNumber,
    this.onAuthSuccess,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.page != null) {
        setState(() {
          _currentPage = _pageController.page!.round();
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToMainScreen() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> onboardingPagesData = [
      {
        'image': 'assets/screen.png',
        'title': "Welcome to SafeStep",
        'subtitle':
            "Your personal safety companion, designed for the unique needs of Sri Lankan women.",
      },
      {
        'image': 'assets/screen2.png',
        'title': "Your Personal Safety Companion",
        'subtitle': "Emergency alerts, real-time location sharing, and safety checks at your fingertips.",
      },
      {
        'image': 'assets/screen3.png',
        'title': "Stay Fearless, Live Free",
        'subtitle': "SafeStep empowers you to live confidently and securely, wherever you go.",
      },
    ];

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: onboardingPagesData.length,
            itemBuilder: (context, index) {
              final isLastPage = index == onboardingPagesData.length - 1;
              return OnboardingPageContent(
                imagePath: onboardingPagesData[index]['image']!,
                title: onboardingPagesData[index]['title']!,
                subtitle: onboardingPagesData[index]['subtitle']!,
                isCurrentPage: _currentPage == index,
                bottomButton: Column(
                  children: [
                    SizedBox(
                      height: 55,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!isLastPage) {
                            _pageController.nextPage(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeIn);
                          } else {
                            _goToMainScreen();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF764ba2),
                          elevation: 6,
                        ),
                        child: Text(
                          isLastPage ? "Get Started" : "Continue",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (!isLastPage) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _goToMainScreen,
                        child: const Text(
                          "Skip",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    ]
                  ],
                ),
              );
            },
          ),

          // Smooth pill-shaped dot indicators
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(onboardingPagesData.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    height: 10,
                    width: _currentPage == index ? 30 : 10,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF764ba2)
                          : const Color(0xFF764ba2).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
