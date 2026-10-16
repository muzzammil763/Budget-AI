import { site } from './site';

// Lines for the scroll companion. Each step attaches to the first element
// matching `anchor` and is spoken when that element reaches the reading
// line. `side` is only a preference: the companion picks the spot beside
// the section where its bubble covers no screenshot and the least text.
export type Mood = 'neutral' | 'happy' | 'surprised' | 'wink' | 'love' | 'curious';

export interface CompanionAction {
  label: string;
  href: string;
  primary?: boolean;
}

export interface CompanionStep {
  anchor: string;
  text: string;
  side?: 'left' | 'right';
  mood?: Mood;
  actions?: CompanionAction[];
}

export interface CompanionScript {
  name: string;
  steps: CompanionStep[];
  exit: { text: string; actions: CompanionAction[] };
  idle: string;
  dismissKey: string;
  /** Screenshots and visuals the bubble must not cover. */
  avoid: string;
  /** Text the bubble should cover as little as possible. */
  text: string;
}

export const companion: CompanionScript = {
  name: 'Budget AI helper',
  dismissKey: 'budgetai-companion-hidden',
  avoid: '.phone, .photo, .compare-frame, .float, .final-card, .p-card, .qa, .trust-item, .pills',
  text: 'h1, h2, h3, p, li, .btn, .eyebrow',
  idle: 'Zzz… budgeting is tiring. Scroll and I’ll wake up.',
  steps: [
    {
      anchor: '.hero-copy',
      side: 'right',
      mood: 'happy',
      text: 'Hi! 👋 I’m the Budget AI helper. Want a quick tour?',
      actions: [
        { label: 'Start the tour', href: '#features', primary: true },
        { label: 'Get the app', href: site.playStoreUrl },
      ],
    },
    {
      anchor: '#f-voice',
      side: 'left',
      mood: 'curious',
      text: 'Hold the mic and say “lunch 14.50 and a cab for 22”. I’ll log both entries.',
    },
    {
      anchor: '#f-receipts',
      side: 'right',
      mood: 'surprised',
      text: 'Snap a receipt and every line gets read. The total is never counted twice.',
    },
    {
      anchor: '#f-categories',
      side: 'left',
      mood: 'wink',
      text: 'No manual tagging. Every entry lands in the right category for you.',
    },
    {
      anchor: '#f-finances',
      side: 'right',
      mood: 'happy',
      text: 'Income in green, spending in red. Search anything and switch months in a tap.',
    },
    {
      anchor: '#f-insights',
      side: 'left',
      mood: 'love',
      text: 'Charts, highlights, and a one-tap AI summary of your month. 📊',
    },
    {
      anchor: '#widgets',
      side: 'right',
      mood: 'happy',
      text: 'Check your spending right from the Home Screen, without opening the app.',
    },
    {
      anchor: '.theme-grid',
      side: 'right',
      mood: 'curious',
      text: 'Light or dark? Drag the slider to compare. 🌗',
    },
    {
      anchor: '#privacy',
      side: 'left',
      mood: 'love',
      text: 'Your chats stay on your phone. No ads, and your data is never sold. 🔒',
    },
    {
      anchor: '#faq',
      side: 'left',
      mood: 'neutral',
      text: 'Got a question? Tap any one, I’ll wait. 🙂',
    },
    {
      anchor: '.final',
      side: 'right',
      mood: 'happy',
      text: 'Ready? Let your next expense log itself.',
      actions: [{ label: 'Get it on Google Play', href: site.playStoreUrl, primary: true }],
    },
  ],
  exit: {
    text: 'Wait! Budget AI is free to download, and no bank connection is needed.',
    actions: [{ label: 'Okay, get Budget AI', href: site.playStoreUrl, primary: true }],
  },
};
