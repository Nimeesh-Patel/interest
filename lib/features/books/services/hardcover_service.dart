import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hardcover_book.dart';

class HardcoverService {
  static const _tokenKey = 'hardcover_api_token';
  static const _endpoint = 'https://api.hardcover.app/v1/graphql';

  // ── Token storage ─────────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // ── Connectivity ──────────────────────────────────────────────────────────

  /// Returns null on success, or a human-readable error string on failure.
  static Future<String?> testConnection(String token) async {
    const query = 'query { me { id } }';
    final (data, error) = await _graphqlDebug(token, query);
    if (data != null) return null;
    return error ?? 'Unknown error';
  }

  /// Like _graphql but returns (data, errorDescription) so callers can surface
  /// the actual failure reason. Only used by testConnection.
  static Future<(Map<String, dynamic>?, String?)> _graphqlDebug(
    String token,
    String query, [
    Map<String, dynamic>? variables,
  ]) async {
    try {
      final body = <String, dynamic>{'query': query};
      if (variables != null) body['variables'] = variables;

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        final preview = response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body;
        return (null, 'HTTP ${response.statusCode}: $preview');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['errors'] != null) {
        final errors = json['errors'] as List?;
        final msg = errors
                ?.map((e) => (e as Map?)?['message']?.toString() ?? e.toString())
                .join('; ') ??
            'GraphQL errors';
        return (null, msg);
      }

      return (json['data'] as Map<String, dynamic>?, null);
    } catch (e) {
      return (null, e.toString());
    }
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  static Future<(List<HardcoverBook>?, String?)> fetchUserBooks(
      String token) async {
    const query = '''
query GetMyBooks {
  me {
    user_books {
      id
      status_id
      rating
      date_added
      first_started_reading_date
      last_read_date
      book {
        id
        title
        cached_contributors
      }
    }
  }
}''';
    final (data, error) = await _graphqlDebug(token, query);
    if (data == null) return (null, error ?? 'No data returned');
    try {
      final meList = data['me'] as List? ?? [];
      final me = meList.isNotEmpty ? meList.first as Map<String, dynamic>? : null;
      final userBooks = me?['user_books'] as List? ?? [];
      final result = <HardcoverBook>[];
      for (final item in userBooks) {
        final book = HardcoverBook.fromJson(item as Map<String, dynamic>);
        if (book != null) result.add(book);
      }
      return (result, null);
    } catch (e) {
      return (null, e.toString());
    }
  }

  static Future<List<HardcoverBook>?> searchBooks(
      String token, String query) async {
    const gql = '''
query SearchBooks(\$query: String!) {
  books(where: {title: {_ilike: \$query}}, limit: 10) {
    id
    title
    cached_contributors
  }
}''';
    final data = await _graphql(token, gql, {'query': '%$query%'});
    if (data == null) return null;
    try {
      final books = data['books'] as List? ?? [];
      final result = <HardcoverBook>[];
      for (final item in books) {
        // searchBooks returns book objects (not user_book), wrap minimally
        final wrapped = {
          'id': 0,
          'status_id': 1,
          'rating': null,
          'date_added': null,
          'first_started_reading_date': null,
          'last_read_date': null,
          'book': item,
        };
        final book = HardcoverBook.fromJson(wrapped);
        if (book != null) result.add(book);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  static Future<bool> updateUserBook(
    String token,
    int userBookId, {
    required int statusId,
    double? rating,
  }) async {
    const gql = '''
mutation UpdateUserBook(\$id: Int!, \$statusId: Int!, \$rating: numeric) {
  update_user_book(
    where: {id: {_eq: \$id}},
    _set: {status_id: \$statusId, rating: \$rating}
  ) {
    returning { id }
  }
}''';
    final variables = <String, dynamic>{
      'id': userBookId,
      'statusId': statusId,
      if (rating != null) 'rating': rating,
    };
    final data = await _graphql(token, gql, variables);
    if (data == null) return false;
    try {
      final returning =
          data['update_user_book']['returning'] as List? ?? [];
      return returning.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<int?> insertUserBook(
      String token, int bookId, int statusId) async {
    const gql = '''
mutation InsertUserBook(\$bookId: Int!, \$statusId: Int!) {
  insert_user_book(object: {book_id: \$bookId, status_id: \$statusId}) {
    id
  }
}''';
    final data = await _graphql(token, gql, {
      'bookId': bookId,
      'statusId': statusId,
    });
    if (data == null) return null;
    try {
      return (data['insert_user_book']['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  // ── Private: GraphQL transport ────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _graphql(
    String token,
    String query, [
    Map<String, dynamic>? variables,
  ]) async {
    try {
      final body = <String, dynamic>{'query': query};
      if (variables != null) body['variables'] = variables;

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['errors'] != null) return null;
      return json['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
