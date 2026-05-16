class PrinterModel {
  final String name;
  final int paperMm;
  final String profile;
  const PrinterModel({required this.name, required this.paperMm, required this.profile});
}

const supportedPrinterModels = <PrinterModel>[
  PrinterModel(name: 'X-Printer X50',  paperMm: 58, profile: 'XP58'),
  PrinterModel(name: 'Sumi v1',        paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2',        paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2s',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2 pro',    paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi SE',        paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sunrise',        paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Capa Z91',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Rovo',           paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Rove Plus',      paperMm: 58, profile: 'default'),
];
