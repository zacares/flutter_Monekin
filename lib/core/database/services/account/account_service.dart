import 'package:async/async.dart' show StreamZip;
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:finlytics/core/database/database_impl.dart';
import 'package:finlytics/core/models/account/account.dart';

enum AccountDataFilter { income, expense, balance }

class AccountService {
  final DatabaseImpl db;

  AccountService._(this.db);
  static final AccountService instance =
      AccountService._(DatabaseImpl.instance);

  Future<int> insertAccount(AccountInDB account) {
    return db.into(db.accounts).insert(account);
  }

  Future<bool> updateAccount(AccountInDB account) {
    return db.update(db.accounts).replace(account);
  }

  Future<int> deleteAccount(String accountId) {
    return (db.delete(db.accounts)..where((tbl) => tbl.id.equals(accountId)))
        .go();
  }

  Stream<List<Account>> getAccounts({
    Expression<bool> Function(Accounts acc, Currencies curr)? predicate,
    OrderBy Function(Accounts acc, Currencies curr)? orderBy,
    int? limit,
    int? offset,
  }) {
    return db
        .getAccountsWithFullData(
          predicate: predicate,
          orderBy: orderBy,
          limit: (a, currency) => Limit(limit ?? -1, offset),
        )
        .watch();
  }

  Stream<Account?> getAccountById(String id) {
    return getAccounts(predicate: (a, c) => a.id.equals(id), limit: 1)
        .map((res) => res.firstOrNull);
  }

  String _joinAccountAndRate(DateTime? date, {String columnName = 'excRate'}) =>
      '''
    LEFT JOIN
      (
          SELECT currencyCode,
                  exchangeRate
            FROM exchangeRates er
            WHERE date = (
                            SELECT MAX(date) 
                              FROM exchangeRates
                              WHERE currencyCode = er.currencyCode 
                              ${date != null ? 'AND  date <= ?' : ''}
                        )
            ORDER BY currencyCode
      )
      AS $columnName ON accounts.currencyId = excRate.currencyCode
    ''';

  /// Get the amount of money that an account have in a certain period of time, specified in the [date] param. If the [date] param is null, it will return the money of the account right now.
  ///
  /// By default, the returned amount will be in the account currency
  Stream<double> getAccountMoney(
      {required Account account,
      DateTime? date,
      bool convertToPreferredCurrency = false}) {
    return getAccountsMoney(
        accountIds: [account.id],
        date: date,
        convertToPreferredCurrency: convertToPreferredCurrency);
  }

  Stream<double> getAccountsMoney(
      {required Iterable<String> accountIds,
      DateTime? date,
      bool convertToPreferredCurrency = true}) {
    date ??= DateTime.now();

    // Get the accounts initial balance (converted to the preferred currency if necessary)
    final initialBalanceQuery = db
        .customSelect(
          """
      SELECT COALESCE(SUM(accounts.iniValue ${convertToPreferredCurrency ? ' * COALESCE(excRate.exchangeRate, 1)' : ''} ), 0) AS balance
      FROM accounts
          ${convertToPreferredCurrency ? _joinAccountAndRate(date) : ''}
          WHERE accounts.id IN (${List.filled(accountIds.length, '?').join(', ')})
      """,
          readsFrom: {
            db.accounts,
            if (convertToPreferredCurrency) db.exchangeRates
          },
          variables: [
            if (convertToPreferredCurrency) Variable.withDateTime(date),
            for (var id in accountIds) Variable.withString(id)
          ],
        )
        .watchSingleOrNull()
        .map((res) {
          if (res?.data != null) {
            return (res!.data['balance'] as num).toDouble();
          }

          return 0.0;
        });

    // Sum the acount initial balance and the balance of the transactions
    return StreamZip([
      initialBalanceQuery,
      getAccountsData(
        accountIds: accountIds,
        accountDataFilter: AccountDataFilter.balance,
        convertToPreferredCurrency: convertToPreferredCurrency,
        endDate: date,
      )
    ]).map((res) => res[0] + res[1]);
  }

  Stream<double> getAccountsData(
      {required Iterable<String> accountIds,
      required AccountDataFilter accountDataFilter,
      Iterable<String>? categoriesIds,
      DateTime? endDate,
      DateTime? startDate,
      bool convertToPreferredCurrency = true}) {
    String transactionWhereStatement = """
        isHidden = 0
        AND status IS NOT 'voided'      
        ${categoriesIds != null ? ' AND transactions.categoryID IN (${List.filled(categoriesIds.length, '?').join(', ')}) ' : ''} 
        ${endDate != null ? ' AND date <= ?' : ''} 
        ${startDate != null ? ' AND date >= ?' : ''} 
        ${accountDataFilter == AccountDataFilter.expense ? ' AND value < 0 AND receivingAccountID IS NULL' : ''} 
        ${accountDataFilter == AccountDataFilter.income ? ' AND value > 0 AND receivingAccountID IS NULL' : ''}
      """;

    List<Variable<Object>> transactionWhereArgs = [
      if (categoriesIds != null)
        for (var id in categoriesIds) Variable.withString(id),
      if (endDate != null) Variable.withDateTime(endDate),
      if (startDate != null) Variable.withDateTime(startDate),
    ];

    return db
        .customSelect("""
        SELECT (COALESCE(SUM(t.value ${convertToPreferredCurrency ? ' * COALESCE(excRate.exchangeRate, 1)' : ''}), 0) + 
          COALESCE(SUM(tr.value ${convertToPreferredCurrency ? ' * COALESCE(excRate.exchangeRate, 1)' : ''}), 0)) 
        AS balance
          FROM accounts
              LEFT JOIN
              (
                  SELECT CASE
                          WHEN receivingAccountID IS NOT NULL THEN (value * -1)
                          ELSE value
                          END as value,
                        accountID
                    FROM transactions
                    WHERE $transactionWhereStatement
              )
              AS t ON accounts.id = t.accountID
              LEFT JOIN
              (
                  SELECT CASE
                          WHEN receivingAccountID IS NOT NULL THEN (COALESCE(valueInDestiny, value))
                          ELSE value
                          END as value,
                        receivingAccountID
                    FROM transactions
                    WHERE $transactionWhereStatement
              )
              AS tr ON accounts.id = tr.receivingAccountID
              ${convertToPreferredCurrency ? _joinAccountAndRate(endDate) : ''}
        WHERE accounts.id IN (${List.filled(accountIds.length, '?').join(', ')})   
      """, readsFrom: {
          db.accounts,
          db.transactions,
          if (convertToPreferredCurrency) db.exchangeRates
        }, variables: [
          ...transactionWhereArgs,
          ...transactionWhereArgs,
          if (endDate != null && convertToPreferredCurrency)
            Variable.withDateTime(endDate),
          for (var id in accountIds) Variable.withString(id)
        ])
        .watchSingleOrNull()
        .map((res) {
          if (res?.data != null) {
            return (res!.data['balance'] as num).toDouble();
          }

          return 0.0;
        });
  }

  Stream<double> getAccountsMoneyVariation(
      {required List<Account> accounts,
      DateTime? startDate,
      DateTime? endDate,
      bool convertToPreferredCurrency = true}) {
    endDate ??= DateTime.now();
    startDate ??= accounts.map((e) => e.date).min;

    final Iterable<String> accountIds = accounts.map((e) => e.id);

    final accountsBalanceStartPeriod = getAccountsMoney(
        accountIds: accountIds,
        date: startDate,
        convertToPreferredCurrency: convertToPreferredCurrency);

    final accountsBalanceEndPeriod = getAccountsMoney(
        accountIds: accountIds,
        date: endDate,
        convertToPreferredCurrency: convertToPreferredCurrency);

    return StreamZip([accountsBalanceStartPeriod, accountsBalanceEndPeriod])
        .map((res) => (res[1] - res[0]) / res[0]);
  }
}
