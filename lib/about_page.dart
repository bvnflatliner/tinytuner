import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Tiny Tuner'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            
            Text(
              'Version: ${_version.isEmpty ? "..." : _version}',
              style: const TextStyle(fontSize: 20),
            ),
      
            const SizedBox(height: 24),
      
            const Text(
              'I am learing Dart and Flutter. '
              'Tiny Tuner is an educational app that listens to the microphone '
              'and detects the sound frequency and the musical note being played. '
              'May work on Android, Linux and Windows.',
              style: TextStyle(fontSize: 18),
            ),
      
            const SizedBox(height: 32),
      
            const Text(
              'Developer',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
      
            const SizedBox(height: 10),
      
            InkWell(
              onTap: () {
                const url = 'https://www.linkedin.com/in/vitalii-borynskyi-06b6a61b8/';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text(
                'LinkedIn profile',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
