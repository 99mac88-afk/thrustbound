// All visible text in English and Russian (mirrors Localization*.swift, plus web-only text).
import { CRASHTIPS, FUELTIPS, NOTICE, PROBLEM, S, TABNAME, TIPS, TOOLHINT, TOOLNAME } from './strings.js';

/** Russian when the browser's first language is Russian, English otherwise. */
export function detectLang(languages = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'en']) {
  const first = String(languages[0] || 'en').toLowerCase();
  return first === 'ru' || first.startsWith('ru-') || first.startsWith('ru_') ? 'ru' : 'en';
}

/** "For security purposes, you can only request this after 42 seconds." → 42 */
export function waitSeconds(message) {
  const m = /after (\d+) seconds?/.exec(String(message || ''));
  return m ? Number(m[1]) : null;
}

export function ruPlural(n, one, few, many) {
  const n100 = Math.abs(n) % 100;
  const n10 = n100 % 10;
  if (n100 >= 11 && n100 <= 14) return many;
  if (n10 === 1) return one;
  if (n10 >= 2 && n10 <= 4) return few;
  return many;
}

const WEB = {
  getApp: ['GET THE APP', 'СКАЧАТЬ'],
  phoneTitle: ['Play on your phone', 'Играй на телефоне'],
  phoneIntro: ['Thrustbound is also an app for iPhone and Android. Your levels and community account work everywhere.',
    'Thrustbound есть и в виде приложения для iPhone и Android. Твои уровни и аккаунт работают везде.'],
  onIPhone: ['You are on an iPhone, so the iPhone app is the one for you:', 'У тебя iPhone, поэтому тебе подходит версия для iPhone:'],
  onAndroid: ['You are on an Android phone, so the Android app is the one for you:', 'У тебя Android, поэтому тебе подходит версия для Android:'],
  onDesktop: ['Open this page on your phone and it will pick the right app, or download one here:',
    'Открой эту страницу на телефоне, и она подберёт нужную версию, или скачай здесь:'],
  recommended: ['RECOMMENDED', 'РЕКОМЕНДУЕМ'],
  iphoneApp: ['iPhone app (.ipa)', 'Для iPhone (.ipa)'],
  androidApp: ['Android app (.apk)', 'Для Android (.apk)'],
  iphoneSteps: ['Install it with AltStore, SideStore or Sideloadly (it is not on the App Store). iOS 15 or later.',
    'Установи через AltStore, SideStore или Sideloadly (в App Store его нет). iOS 15 или новее.'],
  androidSteps: ['Open the downloaded file and allow your browser to install apps when Android asks. Android 7 or later.',
    'Открой скачанный файл и разреши браузеру устанавливать приложения, когда Android спросит. Android 7 или новее.'],
  homeScreenTip: ['No install needed: tap Share, then “Add to Home Screen” to play full screen from your home screen.',
    'Можно без установки: нажми «Поделиться» → «На экран „Домой“», чтобы играть на весь экран.'],
  keepPlaying: ['KEEP PLAYING IN THE BROWSER', 'ИГРАТЬ В БРАУЗЕРЕ'],
  close: ['Close', 'Закрыть'],
  keysHint: ['Keyboard: ← → steer · ↑ or Space gas · Esc pause', 'Клавиатура: ← → руль · ↑ или пробел газ · Esc пауза'],
  allVersions: ['All versions', 'Все версии'],
  deleteLevelMessage: ['It will be removed from this device. A published copy stays online until you delete it in Community → Mine.',
    'Он будет удалён с этого устройства. Опубликованная копия останется в сети, пока ты не удалишь её в разделе «Сообщество» → «Мои».'],
  vibration: ['Vibration', 'Вибрация'],
  vibrationDetail: ['Buzz on landings, bumps and crashes (Android)', 'Отклик при посадках, ударах и авариях (Android)'],
};

export class L10n {
  constructor(lang) {
    this.lang = lang;
    const pick = (pair) => (lang === 'ru' ? pair[1] : pair[0]);
    for (const [k, v] of Object.entries(S)) this[k] = pick(v);
    for (const [k, v] of Object.entries(WEB)) this[k] = pick(v);
    this.crashTips = CRASHTIPS[lang];
    this.fuelTips = FUELTIPS[lang];
    this.tips = TIPS[lang];
    this.pick = pick;
  }

  t(en, ru) { return this.lang === 'ru' ? ru : en; }

  // Level content
  name(level) { return this.lang === 'ru' ? level.nameRu ?? level.name : level.name; }
  hint(level) { return this.lang === 'ru' ? level.hintRu ?? level.hint : level.hint; }
  worldName(world, index) {
    if (!world) return this.t(`World ${index + 1}`, `Мир ${index + 1}`);
    return this.lang === 'ru' ? world.nameRu ?? world.name : world.name;
  }
  worldSubtitle(world) { return world ? (this.lang === 'ru' ? world.subtitleRu ?? world.subtitle : world.subtitle) : ''; }

  // Formatting
  time(seconds) {
    const v = Math.max(0, seconds).toFixed(1);
    return this.lang === 'ru' ? `${v.replace('.', ',')} с` : `${v}s`;
  }
  wholeSeconds(s) { return this.lang === 'ru' ? `${Math.trunc(s)} с` : `${Math.trunc(s)}s`; }
  levelCount(n) { return this.lang === 'ru' ? `${n} ${ruPlural(n, 'уровень', 'уровня', 'уровней')}` : n === 1 ? '1 level' : `${n} levels`; }
  levelLine(label, name) { return this.t(`Level ${label} · ${name}`, `Уровень ${label} · ${name}`); }
  worldTag(i) { return this.t(`WORLD ${i + 1}`, `МИР ${i + 1}`); }
  levelTag(label) { return this.t(`LEVEL ${label}`, `УРОВЕНЬ ${label}`); }
  touchdown(p) { return this.t(`TOUCHDOWN ${p}%`, `ПОСАДКА ${p}%`); }
  attempt(n) { return this.t(`Attempt ${n}`, `Попытка ${n}`); }
  languageAuto(detected) {
    const name = detected === 'ru' ? this.t('Russian', 'русский') : this.t('English', 'английский');
    return this.t(`Follows your device: ${name}`, `Как на устройстве: ${name}`);
  }
  version(v, levels) { return this.t(`Version ${v} · ${this.levelCount(levels)}`, `Версия ${v} · ${this.levelCount(levels)}`); }

  // Online / maker
  ago(date) {
    const secs = (Date.now() - date.getTime()) / 1000;
    if (Math.abs(secs) < 60) return this.t('just now', 'только что');
    try {
      const f = new Intl.RelativeTimeFormat(this.lang === 'ru' ? 'ru' : 'en', { numeric: 'always', style: 'short' });
      const units = [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]];
      for (const [unit, size] of units) if (Math.abs(secs) >= size) return f.format(-Math.round(secs / size), unit);
    } catch { /* old browser */ }
    return date.toLocaleDateString();
  }
  viewsCount(n) { return this.lang === 'ru' ? `${n} ${ruPlural(n, 'просмотр', 'просмотра', 'просмотров')}` : n === 1 ? '1 view' : `${n} views`; }
  likesCount(n) { return this.lang === 'ru' ? `${n} ${ruPlural(n, 'лайк', 'лайка', 'лайков')}` : n === 1 ? '1 like' : `${n} likes`; }
  byAuthor(name) { return this.t(`by ${name}`, `автор: ${name}`); }
  defaultLevelName(n) { return this.t(`My Level ${n}`, `Мой уровень ${n}`); }
  gridSize(c, r) { return `${c}×${r}`; }
  toolName(tool) { return this.pick(TOOLNAME[tool]); }
  toolHint(tool) { return this.pick(TOOLHINT[tool]); }
  bladeSize(n) { return n === 2 ? this.t('Short', 'Короткое') : n === 4 ? this.t('Long', 'Длинное') : this.t('Medium', 'Среднее'); }
  colorName(i) { return i === 1 ? this.t('Teal', 'Бирюзовый') : i === 2 ? this.t('Pink', 'Розовый') : this.t('Gold', 'Золотой'); }
  notice(n) { return this.pick(NOTICE[n]); }
  problem(p) { return this.pick(PROBLEM[p]); }
  rowsCount(n) { return this.lang === 'ru' ? `${n} ${ruPlural(n, 'ряд', 'ряда', 'рядов')}` : `${n} rows`; }
  publishConfirmTitle(name) { return this.t(`Publish “${name}”?`, `Опубликовать «${name}»?`); }
  tabName(tab) { return this.pick(TABNAME[tab]); }
  deleteOnlineTitle(name) { return this.t(`Delete “${name}”?`, `Удалить «${name}»?`); }
  signedInAs(name) { return this.t(`Signed in as ${name}`, `Ты вошёл как ${name}`); }
  codeSentTo(email) {
    return this.t(`We sent a confirmation code to ${email}. Enter it here to finish creating your account.`,
      `Мы отправили код подтверждения на ${email}. Введи его здесь, чтобы завершить создание аккаунта.`);
  }
  resendIn(n) { return this.t(`Send a new code in ${n} s`, `Новый код — через ${n} с`); }

  onlineError(e) {
    const code = e && e.code;
    switch (code) {
      case 'notConfigured': return this.notConfiguredTitle;
      case 'offline': return this.t('No connection. Check your internet and try again.', 'Нет соединения. Проверь интернет и попробуй ещё раз.');
      case 'signInRequired': return this.t('Please sign in again.', 'Войди в аккаунт ещё раз.');
      case 'confirmEmail': return this.t("Your email isn't confirmed yet. We sent you a code.", 'Почта ещё не подтверждена. Мы отправили тебе код.');
      case 'usernameTaken': return this.t('That username is already taken.', 'Это имя уже занято.');
      case 'badUsername': return this.usernameRules;
      case 'badLevel': return this.levelBroken;
      case 'notAllowed': return this.t("You can't do that.", 'Это действие недоступно.');
      default: break;
    }
    const sc = (e && e.serverCode) || '';
    const message = (e && e.message) || '';
    switch (sc) {
      case 'invalid_credentials': return this.t('Wrong email or password.', 'Неверная почта или пароль.');
      case 'user_already_exists':
      case 'email_exists': return this.t('An account with this email already exists.', 'Аккаунт с этой почтой уже существует.');
      case 'weak_password': return this.passwordRules;
      case 'email_address_invalid':
      case 'validation_failed': return this.t("That email address doesn't look right.", 'Похоже, адрес почты указан неверно.');
      case 'email_not_confirmed': return this.t('Confirm your email first (check your inbox).', 'Сначала подтверди почту (проверь входящие).');
      case 'otp_expired': return this.t('That code is wrong or has expired. Check it or send a new one.', 'Код неверный или устарел. Проверь его или запроси новый.');
      case 'email_address_not_authorized':
        return this.t("The server can't send email to this address yet. Its owner needs to set up email sending.",
          'Сервер пока не может отправлять письма на этот адрес. Владельцу нужно настроить отправку почты.');
      case 'over_email_send_rate_limit': {
        const n = waitSeconds(message);
        if (n !== null) return this.t(`Wait ${n} s and try again.`, `Подожди ${n} с и попробуй снова.`);
        return this.t('Too many emails were sent. Try again later.', 'Отправлено слишком много писем. Попробуй позже.');
      }
      case 'over_request_rate_limit': return this.t('Too many tries. Wait a minute and try again.', 'Слишком много попыток. Подожди минуту.');
      default:
        if (/error sending/i.test(message)) return this.t("Couldn't send the email. Try again later.", 'Не удалось отправить письмо. Попробуй позже.');
        if (message.includes('Daily publish limit')) return this.t('You can publish up to 20 levels a day.', 'Можно публиковать до 20 уровней в день.');
        return message || this.t('Something went wrong.', 'Что-то пошло не так.');
    }
  }
}
