.pragma library

var strings = {
    "OpenCode Usage":
        { fr: "Utilisation OpenCode" },
    "Anthropic":
        { fr: "Anthropic" },
    "Subscription":
        { fr: "Abonnement" },
    "5h Rate Window":
        { fr: "Fen\u00eatre 5h" },
    "used":
        { fr: "utilis\u00e9" },
    "Resets in":
        { fr: "R\u00e9initialise dans" },
    "Resetting...":
        { fr: "R\u00e9initialisation..." },
    "7-Day Usage":
        { fr: "Utilisation 7 jours" },
    "sessions":
        { fr: "sessions" },
    "msgs":
        { fr: "msgs" },
    "Daily Activity":
        { fr: "Activit\u00e9 quotidienne" },
    "Token Consumption":
        { fr: "Consommation de tokens" },
    "Today":
        { fr: "Aujourd'hui" },
    "Week":
        { fr: "Semaine" },
    "Month":
        { fr: "Mois" },
    "Models This Week":
        { fr: "Mod\u00e8les cette semaine" },
    "Since":
        { fr: "Depuis" },
    "Monitor your AI coding usage across providers. Currently tracks Anthropic rate limits, token consumption, and estimated costs via OpenCode credentials.":
        { fr: "Surveillez votre utilisation d'IA pour le code. Suit actuellement les limites Anthropic, la consommation de tokens et les co\u00fbts estim\u00e9s via les identifiants OpenCode." },
    "Refresh Interval":
        { fr: "Intervalle de rafra\u00eechissement" },
    "How often to fetch usage data (minutes)":
        { fr: "Fr\u00e9quence de mise \u00e0 jour des donn\u00e9es (minutes)" },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key
    return strings[key][lang]
}
