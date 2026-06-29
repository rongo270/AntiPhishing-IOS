//
//  Localization.swift
//  AntiPhishing
//
//  In-app runtime localization (English / Hebrew), ported from the Android
//  string.xml + values-iw/string.xml. The app toggles language at runtime
//  via the globe button, exactly like the Android app, so we resolve strings
//  manually rather than relying on the system locale.
//

import Foundation

enum L10n {

    private static let en: [String: String] = [
        "app_name": "AntiPhishing",
        "system_protected": "System Protected",
        "protection_disabled": "Protection Disabled",
        "welcome_message": "Your device is being monitored for phishing attempts in real-time.",
        "active_protection": "Active Protection",
        "stats_scanned_today": "Scanned Today",
        "stats_threats_blocked": "Threats Blocked",
        "recent_activity": "Recent Activity",
        "clear_history": "Clear All History",
        "target_browser_label": "Open safe links in:",
        "change_language": "Change Language",
        "scan_qr": "Scan QR Code to check",
        "check_link": "Check a link",
        "paste_link": "Paste or type a link",
        "check_button": "Check Link",
        "enable_protection_first": "Enable protection first to scan QR codes",
        "open_in_safari": "Safari",
        "open_in_app": "In-app browser",
        // Result screens
        "checking_link": "Checking link safety...",
        "checking_qr": "Checking QR code safety...",
        "dangerous_blocked": "Dangerous Link Blocked",
        "dangerous_subtitle": "This link matches a risk signal. Going back is the safer choice.",
        "risk_level": "Risk level",
        "high_risk": "High risk",
        "source": "Source",
        "go_back": "Go Back",
        "open_anyway": "Open Anyway (At Your Own Risk)",
        "link_needs_review": "Link Needs Review",
        "review_subtitle": "We could not confirm this link as safe yet. If you are not sure, going back is the better choice.",
        "status": "Status",
        "unknown": "Unknown",
        "open_link": "Open Link",
        "could_not_check": "Could Not Check Link",
        "server_unreachable": "Server unreachable. The link could not be verified.",
        "safe_message": "The link you entered is not malicious. You are safe 😊",
        "qr_safe_message": "The QR code you scanned is not malicious. You are safe 😊",
        "scan_qr_title": "Scan QR Code",
        "point_camera": "Point your camera at a QR code",
        "camera_permission": "Camera permission is required to scan QR codes",
        "close": "Close",
        "no_link_found": "No valid link found in the text.",
        // Activation flow
        "activate_title": "Activate Protection",
        "activate_intro": "iOS protects links a little differently from Android.",
        "activate_step_share": "Open any link with Share → AntiPhishing (Safari, Messages, WhatsApp, Mail…) to check it first.",
        "activate_step_qr": "Or scan a QR code, or paste a link on the home screen.",
        "activate_step_safe": "Safe links — and ones you choose to continue — open in Safari.",
        "activate_note": "Note: iOS only lets official browser apps become the default, so AntiPhishing checks links through the Share menu instead of replacing your browser.",
        "open_settings": "Open Settings",
        "activate_done": "Activate Protection",
        "verifying_protection": "Checking that protection works…",
        "protection_active_banner": "✅ Protection active — link checking works",
        "protection_active_offline": "⚠️ Protection on, but the checking service is unreachable",
        "protection_off_banner": "Protection turned off"
    ]

    private static let he: [String: String] = [
        "app_name": "AntiPhishing",
        "system_protected": "המערכת מוגנת",
        "protection_disabled": "ההגנה כבויה",
        "welcome_message": "המכשיר שלך מנוטר כעת מפני ניסיונות פישינג בזמן אמת.",
        "active_protection": "הגנה פעילה",
        "stats_scanned_today": "נסרקו היום",
        "stats_threats_blocked": "איומים שנחסמו",
        "recent_activity": "פעילות אחרונה",
        "clear_history": "נקה היסטוריה",
        "target_browser_label": "פתח קישורים בטוחים ב:",
        "change_language": "שינוי שפה",
        "scan_qr": "סרוק קוד QR לבדיקה",
        "check_link": "בדיקת קישור",
        "paste_link": "הדבק או הקלד קישור",
        "check_button": "בדוק קישור",
        "enable_protection_first": "הפעל הגנה תחילה כדי לסרוק קודי QR",
        "open_in_safari": "Safari",
        "open_in_app": "דפדפן מובנה",
        // Result screens
        "checking_link": "בודק את בטיחות הקישור...",
        "checking_qr": "בודק את בטיחות קוד ה-QR...",
        "dangerous_blocked": "קישור מסוכן נחסם",
        "dangerous_subtitle": "הקישור תואם לסימן סיכון. לחזור אחורה היא הבחירה הבטוחה יותר.",
        "risk_level": "רמת סיכון",
        "high_risk": "סיכון גבוה",
        "source": "מקור",
        "go_back": "חזור אחורה",
        "open_anyway": "פתח בכל זאת (על אחריותך)",
        "link_needs_review": "הקישור דורש בדיקה",
        "review_subtitle": "לא הצלחנו לאשר את הקישור כבטוח. אם אינך בטוח, עדיף לחזור אחורה.",
        "status": "סטטוס",
        "unknown": "לא ידוע",
        "open_link": "פתח קישור",
        "could_not_check": "לא ניתן לבדוק את הקישור",
        "server_unreachable": "השרת אינו זמין. לא ניתן היה לאמת את הקישור.",
        "safe_message": "הקישור שהזנת אינו זדוני. אתה מוגן 😊",
        "qr_safe_message": "קוד ה-QR שסרקת אינו זדוני. אתה מוגן 😊",
        "scan_qr_title": "סריקת קוד QR",
        "point_camera": "כוון את המצלמה אל קוד QR",
        "camera_permission": "נדרשת הרשאת מצלמה כדי לסרוק קודי QR",
        "close": "סגור",
        "no_link_found": "לא נמצא קישור תקין בטקסט.",
        // Activation flow
        "activate_title": "הפעלת הגנה",
        "activate_intro": "ב-iOS ההגנה על קישורים עובדת מעט אחרת מאשר באנדרואיד.",
        "activate_step_share": "פתח כל קישור דרך שיתוף ← AntiPhishing (Safari, הודעות, WhatsApp, דוא\"ל…) כדי לבדוק אותו תחילה.",
        "activate_step_qr": "או סרוק קוד QR, או הדבק קישור במסך הבית.",
        "activate_step_safe": "קישורים בטוחים — ואלה שתבחר להמשיך אליהם — ייפתחו ב-Safari.",
        "activate_note": "הערה: iOS מתיר רק לאפליקציות דפדפן רשמיות להיות ברירת המחדל, ולכן AntiPhishing בודקת קישורים דרך תפריט השיתוף במקום להחליף את הדפדפן.",
        "open_settings": "פתח הגדרות",
        "activate_done": "הפעל הגנה",
        "verifying_protection": "בודק שההגנה פועלת…",
        "protection_active_banner": "✅ ההגנה פעילה — בדיקת הקישורים עובדת",
        "protection_active_offline": "⚠️ ההגנה פעילה, אך שירות הבדיקה אינו זמין",
        "protection_off_banner": "ההגנה כובתה"
    ]

    static func string(_ key: String, _ lang: AppLanguage) -> String {
        let table = (lang == .hebrew) ? he : en
        return table[key] ?? en[key] ?? key
    }
}
