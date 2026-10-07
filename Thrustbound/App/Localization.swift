import Foundation

/// The language picked in Settings. `.system` follows the iPhone's language.
enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case russian = "ru"
}

/// A concrete language the game is shown in.
enum Lang: String {
    case en
    case ru

    /// Russian when the first preferred system language is Russian, English otherwise.
    static func detect(from preferred: [String] = Locale.preferredLanguages) -> Lang {
        guard let first = preferred.first?.lowercased() else { return .en }
        return first == "ru" || first.hasPrefix("ru-") || first.hasPrefix("ru_") ? .ru : .en
    }

    static func resolve(_ choice: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> Lang {
        switch choice {
        case .system: return detect(from: preferred)
        case .english: return .en
        case .russian: return .ru
        }
    }
}

/// Every piece of text the player sees, in English and Russian.
struct L10n {
    let lang: Lang

    init(_ lang: Lang) {
        self.lang = lang
    }

    func t(_ en: String, _ ru: String) -> String {
        lang == .ru ? ru : en
    }

    /// Russian plural form for a count: 1 уровень, 2 уровня, 5 уровней.
    static func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n100 = abs(n) % 100
        let n10 = n100 % 10
        if n100 >= 11 && n100 <= 14 { return many }
        if n10 == 1 { return one }
        if n10 >= 2 && n10 <= 4 { return few }
        return many
    }

    // MARK: - Content from levels.json

    func name(_ level: LevelData) -> String {
        lang == .ru ? (level.nameRu ?? level.name) : level.name
    }

    func hint(_ level: LevelData) -> String {
        lang == .ru ? (level.hintRu ?? level.hint) : level.hint
    }

    func worldName(_ world: WorldInfo?, index: Int) -> String {
        guard let world = world else { return t("World \(index + 1)", "Мир \(index + 1)") }
        return lang == .ru ? (world.nameRu ?? world.name) : world.name
    }

    func worldSubtitle(_ world: WorldInfo?) -> String {
        guard let world = world else { return "" }
        return lang == .ru ? (world.subtitleRu ?? world.subtitle) : world.subtitle
    }

    // MARK: - Formatting

    func time(_ seconds: Double) -> String {
        let value = String(format: "%.1f", max(0, seconds))
        return lang == .ru ? value.replacingOccurrences(of: ".", with: ",") + " с" : value + "s"
    }

    func wholeSeconds(_ seconds: Double) -> String {
        lang == .ru ? "\(Int(seconds)) с" : "\(Int(seconds))s"
    }

    func levelCount(_ n: Int) -> String {
        lang == .ru ? "\(n) " + L10n.ruPlural(n, "уровень", "уровня", "уровней") : (n == 1 ? "1 level" : "\(n) levels")
    }

    // MARK: - Main menu

    var tagline: String { t("Defy gravity. Stick the landing.", "Победи гравитацию. Приземлись идеально.") }
    var play: String { t("PLAY", "ИГРАТЬ") }
    var continueGame: String { t("CONTINUE", "ПРОДОЛЖИТЬ") }
    var levelsButton: String { t("LEVELS", "УРОВНИ") }
    var howToButton: String { t("HOW TO", "ОБУЧЕНИЕ") }
    var settingsButton: String { t("SETTINGS", "НАСТРОЙКИ") }
    func levelLine(_ label: String, _ name: String) -> String { t("Level \(label) · \(name)", "Уровень \(label) · \(name)") }
    var levelsFailed: String { t("Levels could not be loaded.", "Не удалось загрузить уровни.") }

    // MARK: - Level select

    var levelsTitle: String { t("Levels", "Уровни") }
    func worldTag(_ index: Int) -> String { t("WORLD \(index + 1)", "МИР \(index + 1)") }

    // MARK: - HUD and banners

    func levelTag(_ label: String) -> String { t("LEVEL \(label)", "УРОВЕНЬ \(label)") }
    var levelOut: String { t("LEVEL OUT TO LAND", "ВЫРОВНЯЙСЯ ДЛЯ ПОСАДКИ") }
    func touchdown(_ percent: Int) -> String { t("TOUCHDOWN \(percent)%", "ПОСАДКА \(percent)%") }

    // MARK: - In-scene labels (SpriteKit)

    var gas: String { t("GAS", "ГАЗ") }
    var steer: String { t("STEER", "РУЛЬ") }
    var thrust: String { t("THRUST", "ТЯГА") }
    var land: String { t("LAND", "ПОСАДКА") }
    var plusFuel: String { t("+FUEL", "+ТОПЛИВО") }
    var lowFuel: String { t("LOW FUEL", "МАЛО ТОПЛИВА") }

    // MARK: - Pause

    var paused: String { t("PAUSED", "ПАУЗА") }
    var resume: String { t("RESUME", "ПРОДОЛЖИТЬ") }
    var restart: String { t("RESTART", "ЗАНОВО") }
    var menu: String { t("MENU", "МЕНЮ") }
    var sound: String { t("Sound", "Звук") }
    var haptics: String { t("Haptics", "Вибрация") }

    // MARK: - Crash / out of fuel

    var crashed: String { t("CRASHED", "АВАРИЯ") }
    var outOfFuel: String { t("OUT OF FUEL", "НЕТ ТОПЛИВА") }
    var tryAgain: String { t("TRY AGAIN", "ЕЩЁ РАЗ") }
    func attempt(_ n: Int) -> String { t("Attempt \(n)", "Попытка \(n)") }

    var crashTips: [String] {
        lang == .ru ? [
            "Садись медленнее: шкала скорости не должна заходить в красное.",
            "Жми ГАЗ короткими импульсами, чтобы зависнуть на месте.",
            "Направляй джойстик туда, куда должен смотреть нос ракеты.",
            "Всё красное смертельно: шипы, мины, лезвия и лазеры.",
            "Лазеры мигают прямо перед включением. Следи за ритмом.",
            "Легко задеть стену не страшно. Удариться сильно — смертельно.",
            "Выровняйся над площадкой, а дальше пусть работает гравитация."
        ] : [
            "Land slower: keep the speed meter out of the red.",
            "Tap GAS in short bursts to hover in place.",
            "Point the stick where you want the nose to go.",
            "Anything red is deadly: spikes, mines, blades and lasers.",
            "Lasers blink right before they switch on. Watch the rhythm.",
            "Scraping a wall gently is fine. Hitting it hard is not.",
            "Line up above the pad, then let gravity do the work."
        ]
    }

    var fuelTips: [String] {
        lang == .ru ? [
            "Собирай оранжевые канистры, чтобы пополнить бак.",
            "Короткие импульсы газа расходуют меньше топлива, чем постоянная тяга.",
            "Выбирай самый прямой маршрут — топлива здесь мало."
        ] : [
            "Grab orange fuel cans to top up your tank.",
            "Short bursts of gas use less fuel than holding it down.",
            "Take the most direct route. Fuel is tight here."
        ]
    }

    // MARK: - Win

    var perfect: String { t("PERFECT!", "ИДЕАЛЬНО!") }
    var landed: String { t("LANDED!", "ПОСАДКА!") }
    var timeLabel: String { t("Time", "Время") }
    var parLabel: String { t("Par", "Норматив") }
    var fuelLeft: String { t("Fuel left", "Остаток топлива") }
    var newBest: String { t("NEW BEST", "РЕКОРД") }
    var underPar: String { t("UNDER PAR", "ЛУЧШЕ НОРМЫ") }
    var allDone: String { t("You conquered every level. Legendary flying, pilot!", "Ты прошёл все уровни. Легендарный полёт, пилот!") }
    var nextLevel: String { t("NEXT LEVEL", "ДАЛЬШЕ") }
    var mainMenu: String { t("MAIN MENU", "ГЛАВНОЕ МЕНЮ") }
    var retry: String { t("RETRY", "ЕЩЁ РАЗ") }

    // MARK: - How to play

    var howToTitle: String { t("How to Play", "Как играть") }
    var letsFly: String { t("LET'S FLY", "ПОЛЕТЕЛИ!") }

    struct Tip {
        let icon: String
        let title: String
        let text: String
    }

    var tips: [Tip] {
        if lang == .ru {
            return [
                Tip(icon: "gamecontroller.fill", title: "Руль",
                    text: "Тяни джойстик слева. Ракета поворачивается носом туда, куда ты его направляешь."),
                Tip(icon: "flame.fill", title: "Газ",
                    text: "Удерживай ГАЗ справа, чтобы включить двигатель. Гравитация всегда тянет вниз, поэтому жми короткими импульсами, чтобы зависнуть."),
                Tip(icon: "arrow.down.to.line", title: "Посадка",
                    text: "Садись на зелёную площадку медленно и ровно. Шкала скорости не должна быть в красной зоне — замри на мгновение."),
                Tip(icon: "star.fill", title: "Звёзды",
                    text: "На каждом уровне спрятаны три звезды. Собери их и приземлись, чтобы они засчитались. Соберёшь все?"),
                Tip(icon: "fuelpump.fill", title: "Топливо",
                    text: "Бак ограничен. Оранжевые канистры добавляют топливо. Поворачивать можно бесплатно — топливо тратит только тяга."),
                Tip(icon: "exclamationmark.triangle.fill", title: "Опасность",
                    text: "Всё красное уничтожает ракету: шипы, мины, вращающиеся лезвия и лазеры. Удар о скалу на большой скорости тоже смертелен."),
                Tip(icon: "wind", title: "Ветер",
                    text: "Голубые зоны с потоками толкают ракету. Наклоняйся против ветра или позволь ему нести тебя."),
                Tip(icon: "key.fill", title: "Ключи",
                    text: "Двери закрыты, пока ты не возьмёшь ключ того же цвета.")
            ]
        }
        return [
            Tip(icon: "gamecontroller.fill", title: "Steer",
                text: "Drag the stick on the left. Your rocket turns to point its nose the way you push."),
            Tip(icon: "flame.fill", title: "Gas",
                text: "Hold GAS on the right to fire the engine. Gravity always pulls you down, so tap it in short bursts to hover."),
            Tip(icon: "arrow.down.to.line", title: "Land",
                text: "Touch down on the green pad slowly and upright. Keep the speed meter out of the red and hold still for a moment."),
            Tip(icon: "star.fill", title: "Stars",
                text: "Each level hides three stars. Grab them and land to keep them. Can you get them all?"),
            Tip(icon: "fuelpump.fill", title: "Fuel",
                text: "Your tank is limited. Orange cans give you more fuel. Rotating is free, only thrust burns fuel."),
            Tip(icon: "exclamationmark.triangle.fill", title: "Danger",
                text: "Anything red destroys your rocket: spikes, mines, spinning blades and lasers. Hitting rock too fast is fatal too."),
            Tip(icon: "wind", title: "Wind",
                text: "Streaming blue zones push your rocket around. Lean into the wind or let it carry you."),
            Tip(icon: "key.fill", title: "Keys",
                text: "Doors block the way until you collect the key with the same colour.")
        ]
    }

    // MARK: - Settings

    var settingsTitle: String { t("Settings", "Настройки") }
    var languageTitle: String { t("Language", "Язык") }
    var languageSystem: String { t("System", "Системный") }
    func languageAuto(_ detected: Lang) -> String {
        let name = detected == .ru ? t("Russian", "русский") : t("English", "английский")
        return t("Follows your iPhone: \(name)", "Как на iPhone: \(name)")
    }
    var languageManual: String { t("Chosen manually", "Выбран вручную") }
    var soundEffects: String { t("Sound effects", "Звуковые эффекты") }
    var soundEffectsDetail: String { t("Engine, pickups and explosions", "Двигатель, бонусы и взрывы") }
    var hapticsDetail: String { t("Vibration on landings, bumps and crashes", "Отклик при посадках, ударах и авариях") }
    var leftHanded: String { t("Left-handed controls", "Управление для левши") }
    var leftHandedDetail: String { t("Put GAS on the left and the stick on the right", "Кнопка ГАЗ слева, джойстик справа") }
    var unlockAll: String { t("Unlock all levels", "Открыть все уровни") }
    var unlockAllDetail: String { t("Play any level without finishing the previous one", "Любой уровень без прохождения предыдущего") }
    var resetProgress: String { t("Reset progress", "Сбросить прогресс") }
    var resetProgressDetail: String { t("Clears stars and best times", "Удаляет звёзды и лучшее время") }
    var resetConfirmTitle: String { t("Reset all progress?", "Сбросить весь прогресс?") }
    var resetConfirmMessage: String {
        t("Your stars and best times will be erased. This can't be undone.",
          "Все звёзды и рекорды будут удалены. Это действие нельзя отменить.")
    }
    var reset: String { t("Reset", "Сбросить") }
    var cancel: String { t("Cancel", "Отмена") }
    func version(_ v: String, levels: Int) -> String { t("Version \(v) · \(levelCount(levels))", "Версия \(v) · \(levelCount(levels))") }
}
