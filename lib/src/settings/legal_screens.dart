import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/budget_mark.dart';
import 'package:budget_ai/src/helpers/toast_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Support and legal contact shown on About, Privacy Policy, and Terms.
const String kSupportEmail = 'budgetaitracker@gmail.com';
const String _effectiveDate = '16 October 2026';

class _LegalSection {
  const _LegalSection(this.title, this.paragraphs, {this.bullets = const []});

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

const _privacyHighlights = [
  (CupertinoIcons.nosign, 'No ads or tracking'),
  (CupertinoIcons.hand_raised, 'We never sell your data'),
  (CupertinoIcons.device_phone_portrait, 'Chat history stays on your device'),
  (CupertinoIcons.trash, 'Delete everything any time'),
];

const _privacySections = [
  _LegalSection(
    'What we collect',
    ['Budget AI only collects what it needs to run your budget:'],
    bullets: [
      'Account: your email address, display name, and a securely hashed password, handled by our authentication provider.',
      'Finances: only if you turn on Cloud Sync, the expense and income entries you add, including amount, category, description, and date. Cloud Sync is off by default.',
      'Preferences: your currency display and message bubble style, so they follow you to other devices.',
      'AI usage: the number of AI messages and tokens used each month, to apply your plan\'s limits.',
      'Subscriptions: if you buy Budget AI Premium, your plan, renewal status, and expiry date. Payments are handled by Google Play; we never see your card details.',
    ],
  ),
  _LegalSection('What stays on your device', [
    'Your chat conversations, attached images, monthly AI summaries, and app preferences such as notifications are stored only on your device and are never synced to our servers.',
    'Unless you turn on Cloud Sync in Budget Hub, your expense and income entries are stored only on your device. You can save a backup file of them from Budget Hub and restore it later. On Android, they are also included in your own encrypted Google device backup, so they can return if you reinstall Budget AI or move to a new phone; only the account that created them can see them. You can turn this off in your phone\'s backup settings.',
    'Home and Lock Screen widgets read a copy of your entries stored on your device.',
  ]),
  _LegalSection('How AI features work', [
    'When you chat, speak, or attach a receipt, the relevant message, image, or recording is sent through our secure server to OpenAI to generate a reply or transcription. Recordings are deleted from your device once transcribed.',
    'OpenAI processes this data to provide the service under its API terms. We do not use your data to train AI models.',
    'Before your first AI request, the app asks for your agreement to this sharing. Nothing is sent until you agree.',
    'If you report an AI reply, that reply and your optional note are sent to us for review. Nothing else from your chat is shared.',
  ]),
  _LegalSection(
    'How we use your data',
    [
      'We use your data only to provide Budget AI: syncing your entries across devices when Cloud Sync is on, answering your questions, logging entries you ask for, and showing insights.',
    ],
    bullets: [
      'We do not show ads.',
      'We do not sell or rent your data.',
      'We do not use third-party analytics or tracking.',
    ],
  ),
  _LegalSection('Where your data is stored', [
    'Synced data is stored with Supabase, our cloud database provider, and protected so that only your signed-in account can read or change your entries. Data travels over encrypted connections (HTTPS).',
  ]),
  _LegalSection('Purchases', [
    'Budget AI Premium is sold through Google Play. We use RevenueCat to verify purchases and keep your plan in sync. RevenueCat receives your purchase details and your Budget AI account ID, never your finances or chats.',
  ]),
  _LegalSection(
    'Permissions',
    ['Budget AI asks for access only when you use the matching feature:'],
    bullets: [
      'Microphone: hold-to-talk voice entries.',
      'Camera and Photos: adding receipts and images to chat.',
      'Notifications: letting you know when a reply is ready.',
      'Face ID or fingerprint: confirming before you delete all chat history.',
    ],
  ),
  _LegalSection('Your choices and rights', [
    'You can view, edit, and delete any entry in Finances. You can delete your account at any time from Budget Hub → Danger Zone → Delete Account, which permanently removes your account and all synced data. You can turn Cloud Sync off at any time; entries already synced stay in your account until you delete it. Signing out removes your data from that device, so entries that are not synced or backed up are lost.',
    'To request a copy of your data or ask any privacy question, email us.',
  ]),
  _LegalSection('Children', [
    'Budget AI is not intended for children under 13, and we do not knowingly collect their data.',
  ]),
  _LegalSection('Changes to this policy', [
    'If we change this policy, we will update the effective date above and, for significant changes, let you know in the app.',
  ]),
];

const _termsSections = [
  _LegalSection('Using Budget AI', [
    'By creating an account or using Budget AI, you agree to these Terms. If you do not agree, please do not use the app.',
  ]),
  _LegalSection('Your account', [
    'You are responsible for keeping your password secure and for activity on your account. Provide a valid email address and keep your sign-in details private.',
  ]),
  _LegalSection('Not financial advice', [
    'Budget AI helps you track and understand your spending. Its answers, summaries, and insights are for information only and are not financial, tax, legal, or investment advice. Consult a qualified professional before making financial decisions.',
  ]),
  _LegalSection('AI accuracy', [
    'AI can make mistakes. It may misread a receipt, pick the wrong category, or summarize incorrectly. Please review entries the app logs for you; you can edit or delete them at any time in Finances.',
  ]),
  _LegalSection(
    'Fair use',
    [
      'AI features have monthly message and token limits that depend on your plan, to keep the service fast and reliable for everyone. You agree not to:',
    ],
    bullets: [
      'Misuse, overload, or attempt to break the service or its security.',
      'Use Budget AI for anything unlawful, harmful, or abusive.',
      'Reverse engineer the app or access other people\'s data.',
    ],
  ),
  _LegalSection(
    'Premium subscriptions',
    [
      'Manual entries, charts, and widgets are free, and every account includes five free AI messages each month. Budget AI Premium (Lite, Plus, and Pro) adds more AI messages each month; the app shows each plan\'s limits and price before you buy.',
    ],
    bullets: [
      'Subscriptions are billed through Google Play monthly or yearly and renew automatically until you cancel.',
      'Cancel at least 24 hours before renewal in Google Play › Payments & subscriptions. You keep Premium until the end of the paid period.',
      'Upgrades start immediately with credit for unused time; downgrades start at your next renewal.',
      'Unused AI messages do not roll over. Limits reset on the first day of each month (UTC).',
      'Refunds follow Google Play\'s refund policy. Uninstalling the app or deleting your account does not cancel a Google Play subscription.',
    ],
  ),
  _LegalSection('Your content', [
    'Your entries, messages, and images remain yours. You give us permission to store and process them only as needed to provide Budget AI, as described in our Privacy Policy.',
  ]),
  _LegalSection('Availability and changes', [
    'We work to keep Budget AI available, but it may sometimes be interrupted. We may change, add, or remove features, and we may update these Terms; continued use after an update means you accept the new Terms.',
  ]),
  _LegalSection('Ending your use', [
    'You can stop using Budget AI and delete your account at any time. We may suspend accounts that break these Terms.',
  ]),
  _LegalSection('Disclaimer and liability', [
    'Budget AI is provided "as is" without warranties of any kind. To the extent permitted by law, we are not liable for indirect or consequential losses, or for decisions you make based on the app\'s information.',
  ]),
];

const _aboutFeatures = [
  (
    CupertinoIcons.chat_bubble_2,
    'Chat with AI',
    'Ask about your money in plain words',
  ),
  (CupertinoIcons.mic, 'Voice entries', 'Hold the mic, speak once, done'),
  (
    CupertinoIcons.doc_text_viewfinder,
    'Receipt scanning',
    'Snap a receipt and it is logged',
  ),
  (
    CupertinoIcons.chart_bar_alt_fill,
    'Insights',
    'Charts, categories and AI summaries',
  ),
  (CupertinoIcons.square_grid_2x2, 'Widgets', 'Your budget on the Home Screen'),
  (
    CupertinoIcons.circle_lefthalf_fill,
    'Light & dark',
    'Looks right, day or night',
  ),
];

Future<void> _emailSupport(BuildContext context, String subject) async {
  final uri = Uri(
    scheme: 'mailto',
    path: kSupportEmail,
    query: 'subject=${Uri.encodeComponent(subject)}',
  );
  final launched = await launchUrl(uri);
  if (!launched && context.mounted) {
    await Clipboard.setData(const ClipboardData(text: kSupportEmail));
    if (context.mounted) {
      showAppToast(context, message: 'Email address copied: $kSupportEmail');
    }
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      appBarTitle: 'Privacy Policy',
      eyebrow: 'PRIVACY POLICY',
      title: 'Your money,\nyour data.',
      intro:
          'Budget AI is built to keep your finances private. This policy explains what we collect, why, and the choices you have.',
      highlights: _privacyHighlights,
      sections: _privacySections,
      emailSubject: 'Budget AI privacy question',
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScreen(
      appBarTitle: 'Terms & Conditions',
      eyebrow: 'TERMS & CONDITIONS',
      title: 'The simple\nrules.',
      intro:
          'These Terms explain how you can use Budget AI and what you can expect from us.',
      sections: _termsSections,
      emailSubject: 'Budget AI terms question',
    );
  }
}

class _LegalDocumentScreen extends StatelessWidget {
  const _LegalDocumentScreen({
    required this.appBarTitle,
    required this.eyebrow,
    required this.title,
    required this.intro,
    required this.sections,
    required this.emailSubject,
    this.highlights = const [],
  });

  final String appBarTitle;
  final String eyebrow;
  final String title;
  final String intro;
  final List<(IconData, String)> highlights;
  final List<_LegalSection> sections;
  final String emailSubject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: _legalAppBar(context, appBarTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          _HeroCard(
            eyebrow: eyebrow,
            title: title,
            body: intro,
            footer: 'Effective $_effectiveDate',
          ),
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PairGrid(
              children: [
                for (final (icon, label) in highlights)
                  _HighlightTile(icon: icon, label: label),
              ],
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < sections.length; i++)
            _SectionCard(number: i + 1, section: sections[i]),
          const SizedBox(height: 4),
          _ContactCard(
            title: 'Questions?',
            body: 'We are happy to help. Write to us any time.',
            onTap: () => _emailSupport(context, emailSubject),
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class AboutBudgetAiScreen extends StatefulWidget {
  const AboutBudgetAiScreen({super.key});

  @override
  State<AboutBudgetAiScreen> createState() => _AboutBudgetAiScreenState();
}

class _AboutBudgetAiScreenState extends State<AboutBudgetAiScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final version = _packageInfo == null
        ? ''
        : 'Version ${_packageInfo!.version} (${_packageInfo!.buildNumber})';
    return Scaffold(
      appBar: _legalAppBar(context, 'About'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            decoration: _cardDecoration(theme),
            child: Column(
              children: [
                const BudgetMarkIcon(size: 84),
                const SizedBox(height: 18),
                Text(
                  'Budget AI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Boldonse',
                    fontSize: 26,
                    height: 1.7,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your AI budget manager. Log expenses by chat, voice, or a photo of a receipt, and see exactly where your money goes.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (version.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.06,
                      ),
                    ),
                    child: Text(
                      version,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Heading(eyebrow: 'WHAT IT DOES', title: 'Everything in one place'),
          const SizedBox(height: 8),
          _PairGrid(
            children: [
              for (final (icon, title, subtitle) in _aboutFeatures)
                _FeatureTile(icon: icon, title: title, subtitle: subtitle),
            ],
          ),
          const SizedBox(height: 20),
          _Heading(eyebrow: 'GET IN TOUCH', title: 'Contact & legal'),
          const SizedBox(height: 8),
          _ContactCard(
            title: 'Email support',
            body: kSupportEmail,
            onTap: () => _emailSupport(context, 'Budget AI feedback'),
            theme: theme,
          ),
          _LinkTile(
            icon: CupertinoIcons.lock_shield,
            title: 'Privacy Policy',
            subtitle: 'What we collect and how it is used',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
          _LinkTile(
            icon: CupertinoIcons.doc_text,
            title: 'Terms & Conditions',
            subtitle: 'The rules for using Budget AI',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Made with care for better money habits.',
            textAlign: TextAlign.center,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

PreferredSizeWidget _legalAppBar(BuildContext context, String title) {
  return AppBar(
    leading: IconButton(
      onPressed: Navigator.of(context).pop,
      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
    ),
    title: Text(title),
  );
}

BoxDecoration _cardDecoration(ThemeData theme) => BoxDecoration(
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.4)),
);

class _Heading extends StatelessWidget {
  const _Heading({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: AppTheme.headingSmall.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.footer,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BudgetMarkIcon(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  eyebrow,
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Boldonse',
              fontSize: 24,
              height: 1.75,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                CupertinoIcons.calendar,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  footer,
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two equal-height tiles per row that grow with their text.
class _PairGrid extends StatelessWidget {
  const _PairGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < children.length ? 8 : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: children[i]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < children.length
                        ? children[i + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  const _HighlightTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _cardDecoration(theme),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.number, required this.section});

  final int number;
  final _LegalSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = AppTheme.bodyMedium.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: _cardDecoration(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  number.toString().padLeft(2, '0'),
                  style: AppTheme.bodySmall.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.title,
                    style: AppTheme.bodyLarge.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            for (final paragraph in section.paragraphs) ...[
              const SizedBox(height: 8),
              Text(paragraph, style: bodyStyle),
            ],
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(child: Text(bullet, style: bodyStyle)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTheme.bodyMedium.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTheme.bodySmall.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.title,
    required this.body,
    required this.onTap,
    required this.theme,
  });

  final String title;
  final String body;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: primary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.mail_solid,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyLarge.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.arrow_up_right,
                  size: 18,
                  color: theme.colorScheme.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: _cardDecoration(theme),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Icon(icon, size: 24, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.bodyMedium.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
