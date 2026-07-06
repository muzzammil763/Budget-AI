import 'package:budget_ai/features/finance/data/finance_service.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';

ToolDefinition buildLoanAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'loan_add',
  description:
      'Add a loan separately from expenses. Use when the user borrowed money from someone or lent money to someone. Do not log loan principal as an expense.',
  parameters: {
    'type': 'object',
    'properties': {
      'direction': {
        'type': 'string',
        'description': 'Either "borrowed" or "lent".',
      },
      'person': {
        'type': 'string',
        'description': 'Person or party the loan is with.',
      },
      'description': {
        'type': 'string',
        'description': 'Optional loan purpose or note.',
      },
      'amount': {
        'type': 'number',
        'description': 'Principal amount in Pakistani Rupees.',
      },
      'date': {
        'type': 'string',
        'description': 'Loan date in YYYY-MM-DD format. Omit for today.',
      },
    },
    'required': ['direction', 'person', 'amount'],
  },
  handler: handler,
);

ToolDefinition buildLoanPaymentAddTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'loan_payment_add',
  description:
      'Add a repayment/payment against an existing loan. Loan repayments are tracked in loans and should not be logged as expenses.',
  parameters: {
    'type': 'object',
    'properties': {
      'loan_id': {
        'type': 'string',
        'description': 'Loan ID. Use loan_list first if needed.',
      },
      'amount': {'type': 'number', 'description': 'Payment amount in Rs.'},
      'date': {
        'type': 'string',
        'description': 'Payment date in YYYY-MM-DD format. Omit for today.',
      },
      'note': {'type': 'string', 'description': 'Optional payment note.'},
    },
    'required': ['loan_id', 'amount'],
  },
  handler: handler,
);

ToolDefinition buildLoanListTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'loan_list',
  description:
      'List loans and repayments. Use to answer loan balance questions or to find a loan ID before adding a repayment.',
  parameters: {
    'type': 'object',
    'properties': {
      'direction': {
        'type': 'string',
        'description': 'Optional filter: borrowed or lent.',
      },
      'open_only': {
        'type': 'boolean',
        'description': 'If true, only show loans with remaining balance.',
      },
    },
  },
  handler: handler,
);

mixin LoanToolHandler {
  Future<dynamic> handleLoanAddRequest(Map<String, dynamic> args) async {
    final directionRaw = (args['direction'] as String? ?? '').trim();
    final person = (args['person'] as String? ?? '').trim();
    final description = (args['description'] as String? ?? '').trim();
    final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = (args['date'] as String? ?? '').trim();

    if (directionRaw.isEmpty) return {'error': 'direction is required'};
    if (person.isEmpty) return {'error': 'person is required'};
    if (amount <= 0) return {'error': 'amount must be greater than 0'};

    final direction = LoanDirection.fromJson(directionRaw);
    final date = dateStr.isNotEmpty
        ? DateTime.tryParse(dateStr) ?? DateTime.now()
        : DateTime.now();

    try {
      final loan = LoanRecord.create(
        direction: direction,
        person: person,
        description: description,
        principal: amount,
        date: DateTime(date.year, date.month, date.day),
        hasTime: false,
      );
      await LoanService.instance.add(loan);
      return _loanToJson(loan);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<dynamic> handleLoanPaymentAddRequest(Map<String, dynamic> args) async {
    final loanId = (args['loan_id'] as String? ?? '').trim();
    final amount = (args['amount'] as num?)?.toDouble() ?? 0.0;
    final dateStr = (args['date'] as String? ?? '').trim();
    final note = (args['note'] as String? ?? '').trim();

    if (loanId.isEmpty) return {'error': 'loan_id is required'};
    if (amount <= 0) return {'error': 'amount must be greater than 0'};

    final date = dateStr.isNotEmpty
        ? DateTime.tryParse(dateStr) ?? DateTime.now()
        : DateTime.now();

    try {
      final payment = LoanPayment.create(
        date: DateTime(date.year, date.month, date.day),
        amount: amount,
        note: note,
      );
      final updated = await LoanService.instance.addPayment(
        loanId: loanId,
        payment: payment,
      );
      if (updated == null) return {'ok': false, 'error': 'Loan not found'};
      return {
        'ok': true,
        'loan': _loanToJson(updated),
        'payment': {
          'id': payment.id,
          'amount': '${FinanceEntry.formatAmount(payment.amount)} Rs',
          'date': payment.date.toIso8601String().split('T').first,
          'note': payment.note,
        },
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<dynamic> handleLoanListRequest(Map<String, dynamic> args) async {
    final directionRaw = (args['direction'] as String? ?? '').trim();
    final openOnly = args['open_only'] == true;
    try {
      var loans = await LoanService.instance.getAll();
      if (directionRaw.isNotEmpty) {
        final direction = LoanDirection.fromJson(directionRaw);
        loans = loans.where((loan) => loan.direction == direction).toList();
      }
      if (openOnly) {
        loans = loans.where((loan) => loan.remainingAmount > 0).toList();
      }
      return {
        'ok': true,
        'count': loans.length,
        'borrowed_remaining':
            '${FinanceEntry.formatAmount(LoanService.instance.totalRemaining(loans, LoanDirection.borrowed))} Rs',
        'lent_remaining':
            '${FinanceEntry.formatAmount(LoanService.instance.totalRemaining(loans, LoanDirection.lent))} Rs',
        'loans': loans.map(_loanToJson).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Map<String, dynamic> _loanToJson(LoanRecord loan) => {
    'ok': true,
    'id': loan.id,
    'direction': loan.direction.storageValue,
    'person': loan.person,
    'description': loan.description,
    'principal': loan.displayPrincipal,
    'paid': loan.displayPaid,
    'remaining': loan.displayRemaining,
    'date': loan.date.toIso8601String().split('T').first,
    'payments': loan.payments
        .map(
          (payment) => {
            'id': payment.id,
            'amount': '${FinanceEntry.formatAmount(payment.amount)} Rs',
            'date': payment.date.toIso8601String().split('T').first,
            'note': payment.note,
          },
        )
        .toList(),
  };
}
