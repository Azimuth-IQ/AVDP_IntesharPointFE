/// Resolved white-label branding for the signed-in session, from
/// `GET /api/entity/branding`. [sliderUrls] are the HQ-managed home-slider images
/// (active, in order); [agentLogoUrl]/[primaryColor]/[secondaryColor] are the
/// caller's nearest Main-Agent (AGENT1) brand — empty for HQ.
class BrandInfo {
  final String agentLogoUrl;
  final String agentBackgroundUrl; // white-label backdrop image (B-049)
  final String primaryColor;   // hex, e.g. #E2AD25 — main colour
  final String secondaryColor; // hex — accent colour
  final List<String> sliderUrls;

  const BrandInfo({
    this.agentLogoUrl = '',
    this.agentBackgroundUrl = '',
    this.primaryColor = '',
    this.secondaryColor = '',
    this.sliderUrls = const [],
  });

  bool get hasColors => primaryColor.isNotEmpty || secondaryColor.isNotEmpty;

  factory BrandInfo.fromJson(Map<String, dynamic> j) => BrandInfo(
        agentLogoUrl: j['agentLogoUrl'] as String? ?? '',
        agentBackgroundUrl: j['agentBackgroundUrl'] as String? ?? '',
        primaryColor: j['agentPrimaryColor'] as String? ?? '',
        secondaryColor: j['agentSecondaryColor'] as String? ?? '',
        sliderUrls: ((j['sliderImagesUrl'] as List<dynamic>?)?.cast<String>() ?? const [])
            .where((u) => u.trim().isNotEmpty)
            .toList(),
      );
}
