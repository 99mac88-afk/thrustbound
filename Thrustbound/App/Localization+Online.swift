import Foundation

/// Text for the level maker, the community and accounts.
extension L10n {
    // MARK: - Shared

    var makerButton: String { t("LEVEL MAKER", "КОНСТРУКТОР") }
    var communityButton: String { t("COMMUNITY", "СООБЩЕСТВО") }
    var editorButton: String { t("EDITOR", "РЕДАКТОР") }
    var done: String { t("Done", "Готово") }
    var ok: String { t("OK", "ОК") }
    var delete: String { t("Delete", "Удалить") }
    var retryShort: String { t("Try again", "Повторить") }
    var loading: String { t("Loading…", "Загрузка…") }

    func ago(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        f.unitsStyle = .short
        if abs(date.timeIntervalSinceNow) < 60 { return t("just now", "только что") }
        return f.localizedString(for: date, relativeTo: Date())
    }

    func viewsCount(_ n: Int) -> String {
        lang == .ru ? "\(n) " + L10n.ruPlural(n, "просмотр", "просмотра", "просмотров") : (n == 1 ? "1 view" : "\(n) views")
    }

    func likesCount(_ n: Int) -> String {
        lang == .ru ? "\(n) " + L10n.ruPlural(n, "лайк", "лайка", "лайков") : (n == 1 ? "1 like" : "\(n) likes")
    }

    // MARK: - Playing custom levels

    func byAuthor(_ name: String) -> String { t("by \(name)", "автор: \(name)") }
    var testFlightTag: String { t("TEST FLIGHT", "ТЕСТОВЫЙ ПОЛЁТ") }
    var communityTag: String { t("COMMUNITY", "СООБЩЕСТВО") }
    var testFlightHint: String {
        t("Land on the goal to prove your level can be beaten.", "Приземлись на финише, чтобы доказать, что уровень проходим.")
    }
    var testCleared: String { t("Level tested! You can publish it now.", "Уровень проверен! Теперь его можно опубликовать.") }
    var like: String { t("Like", "Нравится") }

    // MARK: - Level maker home

    var makerTitle: String { t("Level Maker", "Конструктор") }
    var newLevel: String { t("NEW LEVEL", "НОВЫЙ УРОВЕНЬ") }
    func defaultLevelName(_ n: Int) -> String { t("My Level \(n)", "Мой уровень \(n)") }
    var makerIntro: String {
        t("Draw your own caves, test-fly them and share them with every pilot.",
          "Рисуй свои пещеры, испытывай их и делись ими со всеми пилотами.")
    }
    var openExample: String { t("OPEN THE EXAMPLE", "ОТКРЫТЬ ПРИМЕР") }
    var statusDraft: String { t("Not tested", "Не проверен") }
    var statusTested: String { t("Tested", "Проверен") }
    var statusPublished: String { t("Published", "Опубликован") }
    var statusChanged: String { t("Changed since publishing", "Изменён после публикации") }
    var duplicate: String { t("Duplicate", "Копировать") }
    var copySuffix: String { t(" copy", " (копия)") }
    var deleteLevelTitle: String { t("Delete this level?", "Удалить этот уровень?") }
    var deleteLevelMessage: String {
        t("It will be removed from this iPhone. A published copy stays online until you delete it in Community → Mine.",
          "Он будет удалён с этого iPhone. Опубликованная копия останется в сети, пока ты не удалишь её в разделе «Сообщество» → «Мои».")
    }
    func gridSize(_ cols: Int, _ rows: Int) -> String { "\(cols)×\(rows)" }

    // MARK: - Editor tools

    func toolName(_ tool: EditorTool) -> String {
        switch tool {
        case .rock: return t("Rock", "Скала")
        case .erase: return t("Erase", "Ластик")
        case .hand: return t("Move", "Сдвиг")
        case .start: return t("Start", "Старт")
        case .goal: return t("Goal", "Финиш")
        case .star: return t("Star", "Звезда")
        case .fuel: return t("Fuel", "Топливо")
        case .spikes: return t("Spikes", "Шипы")
        case .mine: return t("Mine", "Мина")
        case .movingMine: return t("Patrol", "Патруль")
        case .spinner: return t("Blade", "Лезвие")
        case .laser: return t("Laser", "Лазер")
        case .wind: return t("Wind", "Ветер")
        case .key: return t("Key", "Ключ")
        case .door: return t("Door", "Дверь")
        }
    }

    func toolHint(_ tool: EditorTool) -> String {
        switch tool {
        case .rock: return t("Drag to draw rock. Two fingers move and zoom.", "Веди пальцем, чтобы рисовать скалу. Двумя пальцами — сдвиг и масштаб.")
        case .erase: return t("Drag to clear rock and objects.", "Веди пальцем, чтобы стирать скалы и предметы.")
        case .hand: return t("Drag to look around. Pinch to zoom.", "Двигай поле пальцем. Щипок — масштаб.")
        case .start: return t("Tap a floor to put the launch pad there.", "Нажми на пол, чтобы поставить стартовую площадку.")
        case .goal: return t("Tap a floor to put the landing pad there.", "Нажми на пол, чтобы поставить финишную площадку.")
        case .star: return t("Tap to place a star (up to 3).", "Нажми, чтобы поставить звезду (до 3).")
        case .fuel: return t("Tap to place a fuel can (+10 fuel).", "Нажми, чтобы поставить канистру (+10 топлива).")
        case .spikes: return t("Tap next to rock. Tap again to turn.", "Нажми рядом со скалой. Ещё раз — повернуть.")
        case .mine: return t("Tap to place a mine.", "Нажми, чтобы поставить мину.")
        case .movingMine: return t("Tap to place, then tap where it patrols to.", "Нажми, чтобы поставить, затем — куда она будет ездить.")
        case .spinner: return t("Tap to place a spinning blade.", "Нажми, чтобы поставить вращающееся лезвие.")
        case .laser: return t("Tap to place a blinking laser. It reaches the rock.", "Нажми, чтобы поставить мигающий лазер. Он достаёт до скалы.")
        case .wind: return t("Pick a direction and tap. Tap again to turn.", "Выбери направление и нажми. Ещё раз — повернуть.")
        case .key: return t("A key opens every door of its colour.", "Ключ открывает все двери своего цвета.")
        case .door: return t("Doors block the way until the key is taken.", "Двери закрыты, пока не взят ключ.")
        }
    }

    var across: String { t("Across", "Поперёк") }
    var upDown: String { t("Up–down", "Вверх–вниз") }
    var clockwise: String { t("Clockwise", "По часовой") }
    var anticlockwise: String { t("Anticlockwise", "Против часовой") }
    func bladeSize(_ n: Int) -> String {
        switch n {
        case 2: return t("Short", "Короткое")
        case 4: return t("Long", "Длинное")
        default: return t("Medium", "Среднее")
        }
    }
    func colorName(_ i: Int) -> String {
        switch i {
        case 1: return t("Teal", "Бирюзовый")
        case 2: return t("Pink", "Розовый")
        default: return t("Gold", "Золотой")
        }
    }

    func notice(_ n: EditorNotice) -> String {
        switch n {
        case .padNeedsFloor: return t("Pads need two rock cells below and room above.", "Площадке нужны две клетки скалы снизу и место сверху.")
        case .cellTaken: return t("That spot is taken.", "Это место занято.")
        case .starLimit: return t("Up to 3 stars per level.", "Не больше 3 звёзд на уровень.")
        case .itemLimit: return t("That's the most objects a level can have.", "Больше предметов на уровне поставить нельзя.")
        case .mineTrack: return t("Now tap where the mine should move to.", "Теперь нажми, куда должна ездить мина.")
        }
    }

    func problem(_ p: LevelCompiler.Problem) -> String {
        switch p {
        case .noStart: return t("Place the launch pad (Start tool).", "Поставь стартовую площадку (инструмент «Старт»).")
        case .noGoal: return t("Place the landing pad (Goal tool).", "Поставь финишную площадку (инструмент «Финиш»).")
        case .startBlocked: return t("The launch pad needs rock under it and room above.", "Стартовой площадке нужна скала снизу и место сверху.")
        case .goalBlocked: return t("The landing pad needs rock under it and room above.", "Финишной площадке нужна скала снизу и место сверху.")
        case .padsOverlap: return t("The two pads overlap.", "Площадки накладываются друг на друга.")
        }
    }

    var notReadyTitle: String { t("Not ready to fly", "Пока нельзя лететь") }
    var test: String { t("TEST", "ТЕСТ") }
    var publish: String { t("PUBLISH", "ОПУБЛИКОВАТЬ") }
    var published: String { t("PUBLISHED", "ОПУБЛИКОВАН") }
    var undo: String { t("Undo", "Отменить") }
    var redo: String { t("Redo", "Повторить") }

    // MARK: - Level settings

    var levelSettings: String { t("Level settings", "Настройки уровня") }
    var nameLabel: String { t("Name", "Название") }
    var themeLabel: String { t("Look", "Оформление") }
    var widthLabel: String { t("Width", "Ширина") }
    var narrow: String { t("Narrow", "Узкий") }
    var wide: String { t("Wide", "Широкий") }
    var heightLabel: String { t("Height", "Высота") }
    func rowsCount(_ n: Int) -> String {
        lang == .ru ? "\(n) " + L10n.ruPlural(n, "ряд", "ряда", "рядов") : "\(n) rows"
    }
    var fuelLabel: String { t("Fuel tank", "Бак") }
    var fuelDetail: String { t("Seconds of thrust. Each fuel can adds 10.", "Секунды тяги. Каждая канистра добавляет 10.") }
    var shrinkWarning: String { t("Making the level smaller removes what's outside it.", "При уменьшении всё, что за границей, удаляется.") }
    var deleteLevel: String { t("Delete level", "Удалить уровень") }

    // MARK: - Publishing

    var publishNeedsTestTitle: String { t("Test it first", "Сначала проверь") }
    var publishNeedsTest: String {
        t("Fly your level and land on the goal. That proves it can be beaten, then you can publish it.",
          "Пролети свой уровень и приземлись на финише. Так будет ясно, что он проходим, — и его можно публиковать.")
    }
    func publishConfirmTitle(_ name: String) -> String { t("Publish “\(name)”?", "Опубликовать «\(name)»?") }
    var publishConfirmMessage: String {
        t("Every pilot will be able to play it. You can delete it later.",
          "Его смогут пройти все пилоты. Удалить его можно в любой момент.")
    }
    var publishAgainMessage: String {
        t("You changed the level since publishing. This publishes it as a new level.",
          "Ты изменил уровень после публикации. Он будет опубликован как новый уровень.")
    }
    var publishedTitle: String { t("Your level is online!", "Твой уровень в сети!") }
    var publishedMessage: String { t("Find it in Community → Mine.", "Он появился в разделе «Сообщество» → «Мои».") }
    var signInToPublish: String { t("Sign in to publish levels.", "Войди, чтобы публиковать уровни.") }

    // MARK: - Community

    var communityTitle: String { t("Community", "Сообщество") }
    func tabName(_ tab: CommunityTab) -> String {
        switch tab {
        case .newest: return t("New", "Новые")
        case .top: return t("Top", "Лучшие")
        case .viewed: return t("Most viewed", "Популярные")
        case .mine: return t("Mine", "Мои")
        }
    }
    var loadMore: String { t("Load more", "Загрузить ещё") }
    var emptyList: String { t("No levels here yet. Be the first to publish one!", "Здесь пока нет уровней. Опубликуй первый!") }
    var emptyMine: String {
        t("You haven't published anything yet. Build a level in the Level Maker!",
          "Ты ещё ничего не опубликовал. Построй уровень в конструкторе!")
    }
    var signInForMine: String { t("Sign in to see the levels you published.", "Войди, чтобы увидеть свои опубликованные уровни.") }
    var signInToLike: String { t("Sign in to like levels.", "Войди, чтобы ставить лайки.") }
    var deleteOnline: String { t("Delete for everyone", "Удалить для всех") }
    func deleteOnlineTitle(_ name: String) -> String { t("Delete “\(name)”?", "Удалить «\(name)»?") }
    var deleteOnlineMessage: String {
        t("It disappears for every player, with its views and likes. This can't be undone.",
          "Он исчезнет у всех игроков вместе с просмотрами и лайками. Это нельзя отменить.")
    }
    var adminBadge: String { t("ADMIN", "АДМИН") }
    var yours: String { t("YOURS", "ТВОЙ") }
    var notConfiguredTitle: String { t("Community server not set up", "Сервер сообщества не настроен") }
    var notConfiguredBody: String {
        t("This copy of Thrustbound isn't connected to a community server yet. Whoever runs the server can enter its address in Account → Server.",
          "Эта копия Thrustbound пока не подключена к серверу сообщества. Владелец сервера может указать его адрес в разделе «Аккаунт» → «Сервер».")
    }
    var levelBroken: String { t("This level couldn't be loaded.", "Не удалось загрузить этот уровень.") }

    // MARK: - Account

    var accountTitle: String { t("Account", "Аккаунт") }
    var signIn: String { t("SIGN IN", "ВОЙТИ") }
    var signUp: String { t("CREATE ACCOUNT", "СОЗДАТЬ АККАУНТ") }
    var signOut: String { t("Sign out", "Выйти") }
    var usernameLabel: String { t("Username", "Имя пилота") }
    var emailLabel: String { t("Email", "Эл. почта") }
    var passwordLabel: String { t("Password", "Пароль") }
    var haveAccount: String { t("I already have an account", "У меня уже есть аккаунт") }
    var needAccount: String { t("Create a new account", "Создать новый аккаунт") }
    var usernameRules: String { t("3–20 letters, numbers or _. Everyone sees it.", "3–20 латинских букв, цифр или _. Его видят все.") }
    var passwordRules: String { t("At least 6 characters.", "Не меньше 6 символов.") }
    func signedInAs(_ name: String) -> String { t("Signed in as \(name)", "Ты вошёл как \(name)") }
    var adminNote: String {
        t("You're an admin: you can delete any community level.", "Ты администратор: можешь удалять любые уровни сообщества.")
    }
    var accountPitch: String {
        t("An account lets you publish levels and like other pilots' levels.",
          "С аккаунтом можно публиковать уровни и ставить лайки уровням других пилотов.")
    }
    var serverTitle: String { t("Server", "Сервер") }
    var serverURL: String { t("Project URL (https://…supabase.co)", "Адрес проекта (https://…supabase.co)") }
    var serverKey: String { t("Public key (anon or publishable)", "Публичный ключ (anon или publishable)") }
    var serverHelp: String {
        t("Only needed if you run the server yourself. In Supabase: Project Settings → API Keys.",
          "Нужно, только если сервер твой. В Supabase: Project Settings → API Keys.")
    }
    var serverSave: String { t("Save server", "Сохранить сервер") }
    var serverInvalid: String { t("Enter an https:// address and the key.", "Введи адрес https:// и ключ.") }
    var useBuiltIn: String { t("Use the built-in server", "Использовать встроенный сервер") }
    var serverCustom: String { t("Using your own server", "Используется свой сервер") }
    var serverBuiltIn: String { t("Using the built-in server", "Используется встроенный сервер") }
    var serverNone: String { t("No server yet", "Сервер не задан") }

    func onlineError(_ e: Error) -> String {
        guard let e = e as? OnlineError else { return t("Something went wrong.", "Что-то пошло не так.") }
        switch e {
        case .notConfigured: return notConfiguredTitle
        case .offline: return t("No connection. Check your internet and try again.", "Нет соединения. Проверь интернет и попробуй ещё раз.")
        case .signInRequired: return t("Please sign in again.", "Войди в аккаунт ещё раз.")
        case .confirmEmail:
            return t("Check your inbox and confirm your email, then sign in.", "Проверь почту, подтверди адрес и затем войди.")
        case .usernameTaken: return t("That username is already taken.", "Это имя уже занято.")
        case .badUsername: return usernameRules
        case .badLevel: return levelBroken
        case .notAllowed: return t("You can't do that.", "Это действие недоступно.")
        case .server(let code, let message):
            switch code ?? "" {
            case "invalid_credentials": return t("Wrong email or password.", "Неверная почта или пароль.")
            case "user_already_exists", "email_exists":
                return t("An account with this email already exists.", "Аккаунт с этой почтой уже существует.")
            case "weak_password": return passwordRules
            case "email_address_invalid", "validation_failed":
                return t("That email address doesn't look right.", "Похоже, адрес почты указан неверно.")
            case "email_not_confirmed":
                return t("Confirm your email first (check your inbox).", "Сначала подтверди почту (проверь входящие).")
            case "over_request_rate_limit", "over_email_send_rate_limit":
                return t("Too many tries. Wait a minute and try again.", "Слишком много попыток. Подожди минуту.")
            default:
                if message.contains("Daily publish limit") {
                    return t("You can publish up to 20 levels a day.", "Можно публиковать до 20 уровней в день.")
                }
                return message
            }
        }
    }
}
