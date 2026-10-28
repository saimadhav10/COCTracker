import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/village.dart';

const newsUrl = 'https://supercell.com/en/games/clashofclans/blog/';
const catalogueUrl =
    'https://raw.githubusercontent.com/saimadhav10/COCTracker/main/assets/catalogue/home.json';

Catalogue decodeCatalogue(String text) {
  final j = jsonDecode(text) as Map<String, dynamic>;
  if (j['schema'] != 2 ||
      j['entries'] is! Map ||
      (j['entries'] as Map).length < 50) {
    throw const FormatException('Unrecognized catalogue format.');
  }
  final entries = Map<String, dynamic>.from(j['entries']);
  for (final value in entries.values) {
    if (value is! Map || value['name'] is! String || value['levels'] is! List) {
      throw const FormatException('Invalid catalogue entry.');
    }
    for (final level in value['levels'] as List) {
      if (level is! Map ||
          level['level'] is! int ||
          level['townHall'] is! num ||
          (level['seconds'] != null && level['seconds'] is! num)) {
        throw const FormatException('Invalid catalogue upgrade.');
      }
    }
  }
  return Catalogue(entries, j['updatedAt'] as String);
}

Future<Catalogue> refreshCatalogue(SharedPreferences prefs) async {
  final response = await http
      .get(Uri.parse(catalogueUrl))
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw Exception('Catalogue server returned ${response.statusCode}.');
  }
  if (response.bodyBytes.length > 5000000) {
    throw const FormatException('Catalogue is too large.');
  }
  final result = decodeCatalogue(response.body);
  await prefs.setString('catalogue.v2', response.body);
  return result;
}

class NewsArticle {
  const NewsArticle(this.title, this.url);
  final String title;
  final String url;
}

Future<List<NewsArticle>> fetchNews() async {
  final response = await http
      .get(Uri.parse(newsUrl))
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) {
    throw Exception('Official news is temporarily unavailable.');
  }
  final document = html.parse(response.body);
  final results = <String, NewsArticle>{};
  for (final anchor in document.querySelectorAll('a[href]')) {
    final href = anchor.attributes['href']!;
    final url = Uri.parse(newsUrl).resolve(href);
    if (url.host != 'supercell.com' ||
        !url.path.startsWith('/en/games/clashofclans/blog/') ||
        url.path == '/en/games/clashofclans/blog/') {
      continue;
    }
    final title = (anchor.querySelector('h2,h3,h4')?.text ?? anchor.text)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (title.length < 8 || title.length > 350) continue;
    results[url.toString()] = NewsArticle(title, url.toString());
  }
  if (results.isEmpty) {
    throw Exception('Open the official blog for the latest news.');
  }
  return results.values.take(20).toList();
}
