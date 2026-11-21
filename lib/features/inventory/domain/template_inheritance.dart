import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// PROD-023: which print template a category uses — the same rule as the backend's
/// `TemplateResolution`, so HQ's preview shows what the paper will print.
///
/// follows its company → the company's template (the built-in default if it has none)
/// its own, or no company → the category's template
///
/// Whole template, never field by field.

/// The company [def] belongs to, or null (no company, or it is not in [companies]).
Company? companyOf(ProductDefinition def, Iterable<Company> companies) {
  if (def.companyId.isEmpty) return null;
  for (final c in companies) {
    if (c.id == def.companyId) return c;
  }
  return null;
}

/// True when [def] prints with [company]'s template. An unknown flag means its own.
bool followsCompany(ProductDefinition def, Company? company) =>
    def.followsCompanyTemplate == true && company != null && def.companyId == company.id;

/// The template the receipt uses for [def].
VoucherTemplate effectiveTemplate(ProductDefinition def, Company? company) =>
    followsCompany(def, company) ? (company!.voucherTemplate ?? const VoucherTemplate()) : def.template;
