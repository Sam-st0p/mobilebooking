// lib/services/product_service.dart

import 'package:dio/dio.dart';
import '../models/product.dart';
import 'api_client.dart';
import 'mock_data.dart';

/// Calls the backend's /mobile/catalog* routes. If API_BASE_URL isn't
/// configured, this transparently falls back to sample data.
class ProductService {
  static Dio get _dio => ApiClient.instance.dio;

  static Future<List<Product>> getActiveProducts() async {
    if (!ApiConfig.isConfigured) return MockData.getActiveProducts();
    try {
      final response = await _dio.get('/mobile/catalog');
      final data = response.data as Map<String, dynamic>;
      final rows = (data['products'] as List).cast<Map<String, dynamic>>();
      return rows.map(Product.fromJson).toList();
    } catch (e) {
      throw Exception(apiErrorMessage(e, fallback: 'Could not load products.'));
    }
  }

  /// Accepts either the product UUID or its slug.
  static Future<Product?> getProductById(String idOrSlug) async {
    if (!ApiConfig.isConfigured) return MockData.getProductById(idOrSlug);
    try {
      final response = await _dio.get('/mobile/catalog/$idOrSlug');
      final data = response.data as Map<String, dynamic>;
      return Product.fromJson(data['product'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Exception(apiErrorMessage(e, fallback: 'Could not load this product.'));
    }
  }
}