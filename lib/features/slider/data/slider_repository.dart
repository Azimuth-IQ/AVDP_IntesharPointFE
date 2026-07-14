import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/slider/domain/pos_slider.dart';

/// HQ-only CRUD for POS sliders (`/api/slider`).
class SliderRepository {
  const SliderRepository(this._api);
  final ApiClient _api;

  Future<List<PosSlider>> list() async {
    final r = await _api.get(Endpoints.slider);
    return _api.unwrap(r, (d) {
      final list = (d as List?) ?? const [];
      return list
          .map((e) => PosSlider.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<PosSlider> create(PosSlider slider) async {
    final r = await _api.post(Endpoints.slider, data: slider.toRequestJson());
    return _api.unwrap(r, (d) => PosSlider.fromJson(d as Map<String, dynamic>));
  }

  Future<PosSlider> update(String id, PosSlider slider) async {
    final r = await _api.put('${Endpoints.slider}/$id', data: slider.toRequestJson());
    return _api.unwrap(r, (d) => PosSlider.fromJson(d as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    await _api.delete('${Endpoints.slider}/$id');
  }

  /// Persist a new display order (server sets each slider's `order` to its index).
  Future<void> reorder(List<String> idsInOrder) async {
    await _api.put(Endpoints.sliderReorder, data: idsInOrder);
  }
}
