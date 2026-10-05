import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:animaple/services/api_service.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('Streaming Server Resolvers', () {
    test('1. UPNShare resolver resolves to valid playable stream', () async {
      const upnEmbed = 'https://animeav1.uns.bio/#iohbzy';
      final res = await ApiService.fetchVideoUrl(upnEmbed);
      expect(res['type'], 'hls');
      final streamUrl = res['url'] as String;
      expect(streamUrl, isNotEmpty);
      expect(streamUrl, contains('.m3u8'));

      // Verify stream is accessible
      final head = await http.get(Uri.parse(streamUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
        'Referer': 'https://animeav1.uns.bio/',
        'Range': 'bytes=0-100',
      });
      expect(head.statusCode, inInclusiveRange(200, 206));

      // Test resolveHighestQualityHls chooses 1080p
      final best = await ApiService.resolveHighestQualityHls(streamUrl, headers: {
        'Referer': 'https://animeav1.uns.bio/',
      });
      expect(best['height'], 1080);
      expect(best['url'], isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('2. Voe resolver resolves to valid playable stream', () async {
      const voeEmbed = 'https://voe.sx/e/m9utughpwjwp';
      final res = await ApiService.fetchVideoUrl(voeEmbed);
      expect(res['type'], anyOf('hls', 'mp4'));
      final streamUrl = res['url'] as String;
      expect(streamUrl, isNotEmpty);

      // Verify stream is accessible
      final head = await http.get(Uri.parse(streamUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
        ...?((res['headers'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString()))),
        'Range': 'bytes=0-100',
      });
      expect(head.statusCode, inInclusiveRange(200, 206));
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('3. Byse resolver resolves to valid playable stream', () async {
      const byseEmbed = 'https://byselapuix.com/e/tof2erk6kak9';
      final res = await ApiService.fetchVideoUrl(byseEmbed);
      expect(res['type'], anyOf('hls', 'embed'));
      final streamUrl = res['url'] as String;
      expect(streamUrl, isNotEmpty);

      if (res['type'] == 'hls') {
        final head = await http.get(Uri.parse(streamUrl), headers: {
          'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)',
          'Referer': 'https://n1mwq.org/',
          'Range': 'bytes=0-100',
        });
        expect(head.statusCode, inInclusiveRange(200, 206));
      }
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('4. MP4Upload resolver resolves to direct mp4 video', () async {
      const mp4Embed = 'https://www.mp4upload.com/embed-2rnb4udygmki.html';
      final res = await ApiService.fetchVideoUrl(mp4Embed);
      expect(res['type'], 'mp4');
      final streamUrl = res['url'] as String;
      expect(streamUrl, isNotEmpty);
      expect(streamUrl, contains('.mp4'));

      final head = await http.get(Uri.parse(streamUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.mp4upload.com/',
        'Range': 'bytes=0-100',
      });
      expect(head.statusCode, inInclusiveRange(200, 206));
    }, timeout: const Timeout(Duration(seconds: 45)));
  });
}
