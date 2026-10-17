// Mirrors lib/src/settings/legal_screens.dart so the app and the website
// always say the same thing. Update both together.

export interface LegalSection {
  title: string;
  paragraphs: string[];
  bullets?: string[];
}

export const privacyHighlights = [
  'No ads or tracking',
  'We never sell your data',
  'Chat history stays on your device',
  'Delete everything any time',
];

export const privacySections: LegalSection[] = [
  {
    title: 'What we collect',
    paragraphs: ['Budget AI only collects what it needs to run your budget:'],
    bullets: [
      'Account: your email address, display name, and a securely hashed password, handled by our authentication provider.',
      'Finances: only if you turn on Cloud Sync, the expense and income entries you add, including amount, category, description, and date. Cloud Sync is off by default.',
      'Preferences: your currency display and message bubble style, so they follow you to other devices.',
      "AI usage: the number of AI messages and tokens used each month, to apply your plan's limits.",
      'Subscriptions: if you buy Budget AI Premium, your plan, renewal status, and expiry date. Payments are handled by Google Play; we never see your card details.',
    ],
  },
  {
    title: 'What stays on your device',
    paragraphs: [
      'Your chat conversations, attached images, monthly AI summaries, and app preferences such as notifications are stored only on your device and are never synced to our servers.',
      'Unless you turn on Cloud Sync in Budget Hub, your expense and income entries are stored only on your device. You can save a backup file of them from Budget Hub and restore it later. On Android, they are also included in your own encrypted Google device backup, so they can return if you reinstall Budget AI or move to a new phone; only the account that created them can see them. You can turn this off in your phone\'s backup settings.',
      'Home and Lock Screen widgets read a copy of your entries stored on your device.',
    ],
  },
  {
    title: 'How AI features work',
    paragraphs: [
      'When you chat, speak, or attach a receipt, the relevant message, image, or recording is sent through our secure server to OpenAI to generate a reply or transcription. Recordings are deleted from your device once transcribed.',
      'OpenAI processes this data to provide the service under its API terms. We do not use your data to train AI models.',
      'Before your first AI request, the app asks for your agreement to this sharing. Nothing is sent until you agree.',
      'If you report an AI reply, that reply and your optional note are sent to us for review. Nothing else from your chat is shared.',
    ],
  },
  {
    title: 'How we use your data',
    paragraphs: [
      'We use your data only to provide Budget AI: syncing your entries across devices when Cloud Sync is on, answering your questions, logging entries you ask for, and showing insights.',
    ],
    bullets: [
      'We do not show ads.',
      'We do not sell or rent your data.',
      'We do not use third-party analytics or tracking.',
    ],
  },
  {
    title: 'Where your data is stored',
    paragraphs: [
      'Synced data is stored with Supabase, our cloud database provider, and protected so that only your signed-in account can read or change your entries. Data travels over encrypted connections (HTTPS).',
    ],
  },
  {
    title: 'Purchases',
    paragraphs: [
      'Budget AI Premium is sold through Google Play. We use RevenueCat to verify purchases and keep your plan in sync. RevenueCat receives your purchase details and your Budget AI account ID, never your finances or chats.',
    ],
  },
  {
    title: 'Permissions',
    paragraphs: ['Budget AI asks for access only when you use the matching feature:'],
    bullets: [
      'Microphone: hold-to-talk voice entries.',
      'Camera and Photos: adding receipts and images to chat.',
      'Notifications: letting you know when a reply is ready.',
      'Face ID or fingerprint: confirming before you delete all chat history.',
    ],
  },
  {
    title: 'Your choices and rights',
    paragraphs: [
      'You can view, edit, and delete any entry in Finances. You can delete your account at any time from Budget Hub → Danger Zone → Delete Account, which permanently removes your account and all synced data. You can turn Cloud Sync off at any time; entries already synced stay in your account until you delete it. Signing out removes your data from that device, so entries that are not synced or backed up are lost.',
      'To request a copy of your data or ask any privacy question, email us.',
    ],
  },
  {
    title: 'Children',
    paragraphs: [
      'Budget AI is not intended for children under 13, and we do not knowingly collect their data.',
    ],
  },
  {
    title: 'Changes to this policy',
    paragraphs: [
      'If we change this policy, we will update the effective date above and, for significant changes, let you know in the app.',
    ],
  },
];

export const termsSections: LegalSection[] = [
  {
    title: 'Using Budget AI',
    paragraphs: [
      'By creating an account or using Budget AI, you agree to these Terms. If you do not agree, please do not use the app.',
    ],
  },
  {
    title: 'Your account',
    paragraphs: [
      'You are responsible for keeping your password secure and for activity on your account. Provide a valid email address and keep your sign-in details private.',
    ],
  },
  {
    title: 'Not financial advice',
    paragraphs: [
      'Budget AI helps you track and understand your spending. Its answers, summaries, and insights are for information only and are not financial, tax, legal, or investment advice. Consult a qualified professional before making financial decisions.',
    ],
  },
  {
    title: 'AI accuracy',
    paragraphs: [
      'AI can make mistakes. It may misread a receipt, pick the wrong category, or summarize incorrectly. Please review entries the app logs for you; you can edit or delete them at any time in Finances.',
    ],
  },
  {
    title: 'Fair use',
    paragraphs: [
      "AI features have monthly message and token limits that depend on your plan, to keep the service fast and reliable for everyone. You agree not to:",
    ],
    bullets: [
      'Misuse, overload, or attempt to break the service or its security.',
      'Use Budget AI for anything unlawful, harmful, or abusive.',
      "Reverse engineer the app or access other people's data.",
    ],
  },
  {
    title: 'Premium subscriptions',
    paragraphs: [
      "Manual entries, charts, and widgets are free, and every account includes five free AI messages each month. Budget AI Premium (Lite, Plus, and Pro) adds more AI messages each month; the app shows each plan's limits and price before you buy.",
    ],
    bullets: [
      'Subscriptions are billed through Google Play weekly, monthly, or yearly and renew automatically until you cancel.',
      'Cancel at least 24 hours before renewal in Google Play › Payments & subscriptions. You keep Premium until the end of the paid period.',
      'Upgrades start immediately with credit for unused time; downgrades start at your next renewal.',
      'Unused AI messages do not roll over. Limits reset on the first day of each month (UTC).',
      "Refunds follow Google Play's refund policy. Uninstalling the app or deleting your account does not cancel a Google Play subscription.",
    ],
  },
  {
    title: 'Your content',
    paragraphs: [
      'Your entries, messages, and images remain yours. You give us permission to store and process them only as needed to provide Budget AI, as described in our Privacy Policy.',
    ],
  },
  {
    title: 'Availability and changes',
    paragraphs: [
      'We work to keep Budget AI available, but it may sometimes be interrupted. We may change, add, or remove features, and we may update these Terms; continued use after an update means you accept the new Terms.',
    ],
  },
  {
    title: 'Ending your use',
    paragraphs: [
      'You can stop using Budget AI and delete your account at any time. We may suspend accounts that break these Terms.',
    ],
  },
  {
    title: 'Disclaimer and liability',
    paragraphs: [
      'Budget AI is provided "as is" without warranties of any kind. To the extent permitted by law, we are not liable for indirect or consequential losses, or for decisions you make based on the app\'s information.',
    ],
  },
];
