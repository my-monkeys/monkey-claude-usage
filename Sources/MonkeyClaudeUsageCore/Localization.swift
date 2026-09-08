import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, en, fr

    public var label: String {
        switch self {
        case .system: "Auto"
        case .en: "English"
        case .fr: "Français"
        }
    }

    static var resolved: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: PreferenceKey.language) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: stored) ?? .system
        guard language == .system else { return language }
        return Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .fr : .en
    }
}

/// Localized string. Keys are English-ish slugs; unknown keys fall through unchanged so
/// a missing translation is visible rather than silently empty.
public func L(_ key: String, _ arguments: CVarArg...) -> String {
    let table = AppLanguage.resolved == .fr ? frenchStrings : englishStrings
    let format = table[key] ?? englishStrings[key] ?? key
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

public enum CoreStrings {
    public static var rateLimited: String { L("rate_limited") }
}

public enum PreferenceKey {
    public static let accounts = "accounts"
    public static let language = "appLanguage"
    public static let pollingMinutes = "pollingMinutes"
    public static let menuBarStyle = "menuBarStyle"
    public static let compactMenuBar = "compactMenuBar"
    public static let notificationsEnabled = "notificationsEnabled"
    public static let retentionDays = "historyRetentionDays"
    public static let selectedAccount = "selectedAccountID"
    public static let chartRange = "chartRange"
    public static let activityRange = "activityRange"
    public static let activityMeasure = "activityMeasure"
}

package let englishStrings: [String: String] = [
    "app_name": "Monkey Claude Usage",
    "accounts": "Accounts",
    "add_account": "Add an account",
    "remove_account": "Remove this account",
    "rename_account": "Name",
    "menu_bar_tag_help": "How this account is labelled in the menu bar",
    "no_account_title": "No account yet",
    "no_account_body": "Add a Claude account to see its limits in the menu bar.",
    "sign_in": "Sign in with Claude",
    "sign_in_hint": "Your browser will open. Approve, then paste the code shown by Claude below.",
    "second_account_hint": "Adding a second account? Sign out of Claude in your browser first, or use a private window — otherwise you will re-authorize the same account.",
    "paste_code": "Paste the code here",
    "validate": "Add",
    "cancel": "Cancel",
    "settings": "Settings",
    "quit": "Quit",
    "refresh": "Refresh",
    "session_window": "Session (5 h)",
    "weekly_window": "Week — all models",
    "weekly_scoped_window": "Week — %@",
    "extra_usage": "Extra usage",
    "resets_in": "resets in %@",
    "reached": "Limit reached",
    "updated_ago": "updated %@ ago",
    "never_updated": "not fetched yet",
    "signed_out": "Session expired — sign in again",
    "rate_limited": "Rate limited by the API, retrying later",
    "history": "History",
    "history_empty": "Not enough readings yet — this fills in as the app polls. For history that already exists, open Local activity.",
    "burned_per_bucket": "Session — burned per %@",
    "weekly_trend": "This week",
    "bucket_hour": "hour",
    "bucket_15min": "15 min",
    "all_models": "All models",
    "activity": "Local activity",
    "activity_subtitle": "Claude Code on this Mac, every account together — the transcripts carry no account.",
    "activity_empty": "No Claude Code transcript found in ~/.claude/projects.",
    "activity_scanning": "Reading the transcripts…",
    "activity_total": "%@ tokens",
    "measure_all_tokens": "All tokens",
    "measure_output": "Output only",
    "range_90d": "90 d",
    "no_activity_in_range": "Nothing in this range.",
    "range_6h": "6 h",
    "range_24h": "24 h",
    "range_7d": "7 d",
    "range_30d": "30 d",
    "polling_interval": "Refresh every",
    "minutes": "%d min",
    "menu_bar": "Menu bar",
    "style_bars": "Bars",
    "style_logo": "Icon",
    "style_both": "Icon + bars",
    "compact": "Compact bars",
    "notifications": "Notify at 80 %, 95 % and when a limit is reached",
    "language": "Language",
    "retention": "Keep history for",
    "days": "%d days",
    "launch_at_login": "Launch at login",
    "delete_confirm": "Remove %@ from the app? Its tokens and history are deleted; the Claude account itself is untouched.",
    "remove": "Remove",
]

package let frenchStrings: [String: String] = [
    "app_name": "Monkey Claude Usage",
    "accounts": "Comptes",
    "add_account": "Ajouter un compte",
    "remove_account": "Retirer ce compte",
    "rename_account": "Nom",
    "menu_bar_tag_help": "Comment ce compte est étiqueté dans la barre de menus",
    "no_account_title": "Aucun compte",
    "no_account_body": "Ajoutez un compte Claude pour suivre ses limites dans la barre de menus.",
    "sign_in": "Se connecter avec Claude",
    "sign_in_hint": "Le navigateur va s'ouvrir. Autorisez, puis collez ci-dessous le code affiché par Claude.",
    "second_account_hint": "Pour un deuxième compte : déconnectez-vous de Claude dans le navigateur, ou utilisez une fenêtre privée — sinon vous ré-autoriserez le même compte.",
    "paste_code": "Collez le code ici",
    "validate": "Ajouter",
    "cancel": "Annuler",
    "settings": "Réglages",
    "quit": "Quitter",
    "refresh": "Actualiser",
    "session_window": "Session (5 h)",
    "weekly_window": "Semaine — tous modèles",
    "weekly_scoped_window": "Semaine — %@",
    "extra_usage": "Consommation supplémentaire",
    "resets_in": "réinitialisation dans %@",
    "reached": "Limite atteinte",
    "updated_ago": "il y a %@",
    "never_updated": "pas encore relevé",
    "signed_out": "Session expirée — reconnectez-vous",
    "rate_limited": "Trop de requêtes, nouvelle tentative plus tard",
    "history": "Historique",
    "history_empty": "Pas encore assez de relevés — cela se remplit au fil du temps. Pour un historique déjà constitué, ouvrez l’activité locale.",
    "burned_per_bucket": "Session — brûlé par %@",
    "weekly_trend": "Cette semaine",
    "bucket_hour": "heure",
    "bucket_15min": "15 min",
    "all_models": "Tous modèles",
    "activity": "Activité locale",
    "activity_subtitle": "Claude Code sur ce Mac, tous comptes confondus — les transcriptions ne portent aucun compte.",
    "activity_empty": "Aucune transcription Claude Code dans ~/.claude/projects.",
    "activity_scanning": "Lecture des transcriptions…",
    "activity_total": "%@ jetons",
    "measure_all_tokens": "Tous les jetons",
    "measure_output": "Sortie seule",
    "range_90d": "90 j",
    "no_activity_in_range": "Rien sur cette plage.",
    "range_6h": "6 h",
    "range_24h": "24 h",
    "range_7d": "7 j",
    "range_30d": "30 j",
    "polling_interval": "Actualiser toutes les",
    "minutes": "%d min",
    "menu_bar": "Barre de menus",
    "style_bars": "Barres",
    "style_logo": "Icône",
    "style_both": "Icône + barres",
    "compact": "Barres compactes",
    "notifications": "Prévenir à 80 %, 95 % et à la limite atteinte",
    "language": "Langue",
    "retention": "Conserver l'historique",
    "days": "%d jours",
    "launch_at_login": "Lancer à l'ouverture de session",
    "delete_confirm": "Retirer %@ de l'application ? Ses jetons et son historique sont supprimés ; le compte Claude n'est pas touché.",
    "remove": "Retirer",
]

extension UsageLimit {
    /// Human label for the popover.
    public var fullLabel: String {
        if let modelName, !modelName.isEmpty { return L("weekly_scoped_window", modelName) }
        return isSession ? L("session_window") : L("weekly_window")
    }
}
