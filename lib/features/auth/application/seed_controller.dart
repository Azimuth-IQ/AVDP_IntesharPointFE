import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';

final seedControllerProvider =
    AsyncNotifierProvider<SeedController, void>(SeedController.new);

class SeedController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> seed(BuildContext context) async {
    final authState = ref.read(authStateProvider).valueOrNull;
    if (authState is! AuthAuthenticated) return;
    final hqId = authState.entity.id;

    final api = ref.read(apiClientProvider);
    final entityRepo = EntityRepository(api);
    final defRepo = DefinitionRepository(api);
    final productRepo = ProductRepository(api);
    final txRepo = TransactionRepository(api);

    Future<void> tryCreate(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        // Ignore 409/duplicate for idempotency.
        if (!e.toString().contains('409') &&
            !e.toString().contains('duplicate')) {
          rethrow;
        }
      }
    }

    // 1. Baghdad AGENT1
    await tryCreate(() => entityRepo
        .create(
          Entity(
            id: 'baghdad-1',
            meta: const EntityMeta(
              name: 'Baghdad',
              slogan: 'Full Cover ... From Karkh to Rusafa',
              description: 'Distribution of Baghdad',
            ),
            parent: hqId,
            type: EntityType.AGENT1,
          ),
        )
        .then((_) => entityRepo.relinkChildToParent(hqId, 'baghdad-1')));

    // 2. Rusafa AGENT2
    await tryCreate(() => entityRepo
        .create(
          Entity(
            id: 'rusafa-1',
            meta: const EntityMeta(
              name: 'Rusafa',
              description: 'Rusafa local distributor',
            ),
            parent: 'baghdad-1',
            type: EntityType.AGENT2,
          ),
        )
        .then((_) =>
            entityRepo.relinkChildToParent('baghdad-1', 'rusafa-1')));

    // 3. Waleed Mobile STORE with POS user
    await tryCreate(() => entityRepo
        .create(
          Entity(
            id: 'waleed-1',
            meta: const EntityMeta(
              name: 'Waleed Mobile',
              description: 'Voucher retail',
            ),
            parent: 'rusafa-1',
            type: EntityType.STORE,
            users: const [
              EntityUser(
                phone: '07701112222',
                password: 'password',
                role: UserRole.USER,
              ),
            ],
          ),
          includeUsers: true,
        )
        .then(
            (_) => entityRepo.relinkChildToParent('rusafa-1', 'waleed-1')));

    // 4. Product definition
    ProductDefinition def;
    try {
      def = await defRepo.create(const ProductDefinition(
        id: 'def-ac5',
        name: 'Asiacell 5000',
        description: 'Asiacell 5000 IQD Voucher',
        imageUrl: '',
        defaultPrice: '5000',
        sku: 'AC5',
      ));
    } catch (_) {
      def = const ProductDefinition(
        id: 'def-ac5',
        name: 'Asiacell 5000',
        description: '',
        imageUrl: '',
        defaultPrice: '5000',
        sku: 'AC5',
      );
    }

    // 5. Five products on HQ
    for (var i = 1; i <= 5; i++) {
      await tryCreate(() => productRepo.create(Product(
            id: 'prod-${100 + i}',
            productDefinition: def,
            status: ProductStatus.AVAILABLE,
            serialNumber: 'SN10${i.toString().padLeft(2, '0')}',
            pin: 'PIN10${i.toString().padLeft(2, '0')}',
            owners: [hqId],
            currentOwner: hqId,
          )));
    }

    // 6. Transaction HQ → Baghdad
    final now = DateTime.now();
    await tryCreate(() => txRepo.create(AppTransaction(
          date: Formatters.date(now),
          time: Formatters.time(now),
          sourceId: hqId,
          destinationId: 'baghdad-1',
          lines: const [
            TransactionLine(
              id: 'line_1',
              sku: 'AC5',
              amount: '1',
              price: '5000',
              lineTotal: '5000',
            ),
          ],
        )));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commonSeedSuccess)),
      );
    }
  }
}
