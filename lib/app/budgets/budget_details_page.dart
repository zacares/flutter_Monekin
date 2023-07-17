import 'package:drift/drift.dart' as drift;
import 'package:finlytics/app/budgets/budget_form_page.dart';
import 'package:finlytics/app/budgets/budgets_page.dart';
import 'package:finlytics/app/budgets/components/budget_evolution_chart.dart';
import 'package:finlytics/app/home/card_with_header.dart';
import 'package:finlytics/app/transactions/transaction_list.dart';
import 'package:finlytics/core/database/database_impl.dart';
import 'package:finlytics/core/database/services/budget/budget_service.dart';
import 'package:finlytics/core/database/services/transaction/transaction_service.dart';
import 'package:finlytics/core/models/budget/budget.dart';
import 'package:finlytics/core/models/transaction/transaction.dart';
import 'package:finlytics/core/presentation/widgets/animated_progress_bar.dart';
import 'package:finlytics/core/presentation/widgets/currency_displayer.dart';
import 'package:finlytics/core/presentation/widgets/finlytics_popup_menu_button.dart';
import 'package:finlytics/core/presentation/widgets/skeleton.dart';
import 'package:finlytics/core/utils/list_tile_action_item.dart';
import 'package:finlytics/i18n/translations.g.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/presentation/widgets/empty_indicator.dart';

class BudgetDetailsPage extends StatefulWidget {
  const BudgetDetailsPage({super.key, required this.budget});

  final Budget budget;

  @override
  State<BudgetDetailsPage> createState() => _BudgetDetailsPageState();
}

class _BudgetDetailsPageState extends State<BudgetDetailsPage> {
  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.budgets.details.title),
          bottom: TabBar(tabs: [
            Tab(text: t.budgets.details.statistics),
            Tab(text: t.general.transactions),
          ]),
          actions: [
            FinlyticsPopuMenuButton(actionItems: [
              ListTileActionItem(
                label: t.budgets.form.edit,
                icon: Icons.edit,
                onClick: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BudgetFormPage(
                            prevPage: const BudgetsPage(),
                            budgetToEdit: widget.budget),
                      ));
                },
              ),
              ListTileActionItem(
                label: t.general.delete,
                icon: Icons.delete,
                onClick: () async {
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text(t.budgets.delete),
                        content: Text(t.budgets.delete_warning),
                        actions: [
                          TextButton(
                            child: Text(t.general.confirm),
                            onPressed: () {
                              BudgetServive.instance
                                  .deleteBudget(widget.budget.id)
                                  .then((value) {
                                Navigator.pop(context);

                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(t.general.delete)));
                              }).catchError((err) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('$err')));
                              }).whenComplete(() => Navigator.pop(context));
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              )
            ])
          ],
        ),
        body: TabBarView(children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CardWithHeader(
                    title: widget.budget.name,
                    body: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    t.budgets.details.you_already_expend,
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  StreamBuilder(
                                      stream: widget.budget.currentValue,
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return const Skeleton(
                                              width: 25, height: 16);
                                        }

                                        return CurrencyDisplayer(
                                          amountToConvert: snapshot.data!,
                                          textStyle: Theme.of(context)
                                              .textTheme
                                              .headlineSmall!
                                              .copyWith(
                                                  fontWeight: FontWeight.w700),
                                        );
                                      }),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    t.budgets.details.budget_value,
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  CurrencyDisplayer(
                                    amountToConvert: widget.budget.limitAmount,
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .headlineSmall!
                                        .copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        StreamBuilder(
                            stream: widget.budget.percentageAlreadyUsed,
                            builder: (context, snapshot) {
                              final budgetValue = snapshot.data;

                              return AnimatedProgressBar(
                                value: budgetValue != null && budgetValue >= 1
                                    ? 1
                                    : budgetValue ?? 0,
                                color: budgetValue != null && budgetValue >= 1
                                    ? Colors.red
                                    : null,
                              );
                            })
                      ],
                    )),
                const SizedBox(height: 16),
                CardWithHeader(
                    title: 'Datos del presupuesto',
                    body: Column(
                      children: [
                        ListTile(
                            title: Text(t.general.time.periodicity.display),
                            trailing: Text(widget.budget.intervalPeriod
                                    ?.allThePeriodsText(context) ??
                                t.general.time.periodicity.no_repeat)),
                        const Divider(indent: 12),
                        ListTile(
                            title: Text(t.general.time.start_date),
                            trailing: Text(DateFormat.yMMMd()
                                .format(widget.budget.currentDateRange[0]))),
                        const Divider(indent: 12),
                        ListTile(
                            title: Text(t.general.time.end_date),
                            trailing: Text(DateFormat.yMMMd()
                                .format(widget.budget.currentDateRange[1]))),
                        const Divider(indent: 12),
                        ListTile(
                          title: Text(t.budgets.details.expend_diary_left),
                          trailing: StreamBuilder(
                              stream: widget.budget.currentValue,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Skeleton(width: 25, height: 16);
                                }

                                return CurrencyDisplayer(
                                    amountToConvert:
                                        ((widget.budget.limitAmount -
                                                    snapshot.data!) >
                                                0)
                                            ? ((widget.budget.limitAmount -
                                                    snapshot.data!) /
                                                widget.budget.daysLeft)
                                            : 0);
                              }),
                        )
                      ],
                    )),
                const SizedBox(height: 16),
                CardWithHeader(
                    title: t.budgets.details.expend_evolution,
                    body: BudgetEvolutionChart(budget: widget.budget))
              ],
            ),
          ),
          StreamBuilder(
              stream: TransactionService.instance.getTransactions(
                predicate: (transaction, account, accountCurrency,
                        receivingAccount, receivingAccountCurrency, c, p6) =>
                    DatabaseImpl.instance.buildExpr([
                  c.id.isIn(widget.budget.categories) |
                      c.parentCategoryID.isIn(widget.budget.categories),
                  transaction.accountID.isIn(widget.budget.accounts),
                  transaction.isHidden.isNotValue(true),
                  transaction.date
                      .isBiggerThanValue(widget.budget.currentDateRange[0]),
                  transaction.date
                      .isSmallerThanValue(widget.budget.currentDateRange[1]),
                  transaction.status.isNotInValues(
                      [TransactionStatus.pending, TransactionStatus.voided])
                ]),
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Column(
                    children: [LinearProgressIndicator()],
                  );
                }

                final transactions = snapshot.data!;

                if (transactions.isEmpty) {
                  return Column(
                    children: [
                      Expanded(
                          child: EmptyIndicator(
                              title: t.general.empty_warn,
                              description: t.budgets.details.no_transactions)),
                    ],
                  );
                }

                return TransactionListComponent(
                    transactions: transactions,
                    prevPage: BudgetDetailsPage(
                      budget: widget.budget,
                    ));
              })
        ]),
      ),
    );
  }
}
