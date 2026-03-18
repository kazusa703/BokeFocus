import SwiftUI

// MARK: - Language definition

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ja, hi, es, ar, fr, de

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .en: "English"
        case .ja: "日本語"
        case .hi: "हिन्दी"
        case .es: "Español"
        case .ar: "العربية"
        case .fr: "Français"
        case .de: "Deutsch"
        }
    }

    var isRTL: Bool {
        self == .ar
    }
}

// MARK: - Language manager

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        current = AppLanguage(rawValue: saved) ?? .en
    }
}

// MARK: - Localized strings

enum L {
    static var lang: AppLanguage {
        LanguageManager.shared.current
    }

    /// Home
    static var appName: String {
        "BokeFocus"
    }

    static var tagline: String {
        switch lang {
        case .en: "Precise background blur"
        case .ja: "精密な背景ぼかし"
        case .hi: "सटीक बैकग्राउंड ब्लर"
        case .es: "Desenfoque de fondo preciso"
        case .ar: "ضبابية خلفية دقيقة"
        case .fr: "Flou d'arrière-plan précis"
        case .de: "Präzise Hintergrundunschärfe"
        }
    }

    static var howToSelect: String {
        switch lang {
        case .en: "Tap or draw a box to select the subject"
        case .ja: "タップまたはボックスを描いて対象を選択"
        case .hi: "विषय चुनने के लिए टैप करें या बॉक्स बनाएं"
        case .es: "Toca o dibuja un cuadro para seleccionar"
        case .ar: "انقر أو ارسم مربعًا لتحديد الهدف"
        case .fr: "Appuyez ou dessinez un cadre pour sélectionner"
        case .de: "Tippen oder Rahmen zeichnen zum Auswählen"
        }
    }

    static var howToRefine: String {
        switch lang {
        case .en: "Add points to refine the selection"
        case .ja: "ポイントを追加して選択を調整"
        case .hi: "चयन को परिष्कृत करने के लिए पॉइंट जोड़ें"
        case .es: "Agrega puntos para refinar la selección"
        case .ar: "أضف نقاطًا لتحسين التحديد"
        case .fr: "Ajoutez des points pour affiner la sélection"
        case .de: "Punkte hinzufügen zur Verfeinerung"
        }
    }

    static var howToBlur: String {
        switch lang {
        case .en: "Adjust blur intensity with the slider"
        case .ja: "スライダーでぼかしの強さを調整"
        case .hi: "स्लाइडर से ब्लर तीव्रता समायोजित करें"
        case .es: "Ajusta la intensidad del desenfoque"
        case .ar: "اضبط شدة الضبابية بالمنزلق"
        case .fr: "Réglez l'intensité du flou avec le curseur"
        case .de: "Unschärfe mit dem Regler anpassen"
        }
    }

    static var howToBrush: String {
        switch lang {
        case .en: "Fine-tune with the brush tool"
        case .ja: "ブラシツールで微調整"
        case .hi: "ब्रश टूल से फाइन-ट्यून करें"
        case .es: "Ajuste fino con el pincel"
        case .ar: "ضبط دقيق بأداة الفرشاة"
        case .fr: "Peaufinez avec l'outil pinceau"
        case .de: "Feinabstimmung mit dem Pinsel"
        }
    }

    static var choosePhoto: String {
        switch lang {
        case .en: "Choose Photo"
        case .ja: "写真を選択"
        case .hi: "फोटो चुनें"
        case .es: "Elegir foto"
        case .ar: "اختر صورة"
        case .fr: "Choisir une photo"
        case .de: "Foto auswählen"
        }
    }

    /// Editor
    static var analyzing: String {
        switch lang {
        case .en: "Analyzing..."
        case .ja: "分析中..."
        case .hi: "विश्लेषण..."
        case .es: "Analizando..."
        case .ar: "جاري التحليل..."
        case .fr: "Analyse..."
        case .de: "Analyse..."
        }
    }

    static var tapOrDraw: String {
        switch lang {
        case .en: "Tap or draw a box to select"
        case .ja: "タップまたはボックスを描いて選択"
        case .hi: "चुनने के लिए टैप करें या बॉक्स बनाएं"
        case .es: "Toca o dibuja para seleccionar"
        case .ar: "انقر أو ارسم للتحديد"
        case .fr: "Appuyez ou dessinez pour sélectionner"
        case .de: "Tippen oder zeichnen zum Auswählen"
        }
    }

    static var tapToRefine: String {
        switch lang {
        case .en: "Tap to refine selection"
        case .ja: "タップして選択を調整"
        case .hi: "चयन सुधारने के लिए टैप करें"
        case .es: "Toca para refinar"
        case .ar: "انقر لتحسين التحديد"
        case .fr: "Appuyez pour affiner"
        case .de: "Tippen zum Verfeinern"
        }
    }

    static var adjustBlur: String {
        switch lang {
        case .en: "Adjust blur, then tap Next"
        case .ja: "ぼかしを調整して「次へ」をタップ"
        case .hi: "ब्लर समायोजित करें, फिर अगला टैप करें"
        case .es: "Ajusta el desenfoque, luego toca Siguiente"
        case .ar: "اضبط الضبابية ثم انقر التالي"
        case .fr: "Réglez le flou, puis appuyez sur Suivant"
        case .de: "Unschärfe anpassen, dann Weiter tippen"
        }
    }

    static var next: String {
        switch lang {
        case .en: "Next"
        case .ja: "次へ"
        case .hi: "अगला"
        case .es: "Siguiente"
        case .ar: "التالي"
        case .fr: "Suivant"
        case .de: "Weiter"
        }
    }

    static var include: String {
        switch lang {
        case .en: "Include"
        case .ja: "含める"
        case .hi: "शामिल"
        case .es: "Incluir"
        case .ar: "تضمين"
        case .fr: "Inclure"
        case .de: "Einschließen"
        }
    }

    static var exclude: String {
        switch lang {
        case .en: "Exclude"
        case .ja: "除外"
        case .hi: "बाहर"
        case .es: "Excluir"
        case .ar: "استبعاد"
        case .fr: "Exclure"
        case .de: "Ausschließen"
        }
    }

    static var blur: String {
        switch lang {
        case .en: "Blur"
        case .ja: "ぼかし"
        case .hi: "ब्लर"
        case .es: "Desenfoque"
        case .ar: "ضبابية"
        case .fr: "Flou"
        case .de: "Unschärfe"
        }
    }

    /// Refine
    static var refine: String {
        switch lang {
        case .en: "Refine"
        case .ja: "調整"
        case .hi: "परिष्कृत"
        case .es: "Refinar"
        case .ar: "تحسين"
        case .fr: "Affiner"
        case .de: "Verfeinern"
        }
    }

    static var save: String {
        switch lang {
        case .en: "Save"
        case .ja: "保存"
        case .hi: "सहेजें"
        case .es: "Guardar"
        case .ar: "حفظ"
        case .fr: "Enregistrer"
        case .de: "Speichern"
        }
    }

    static var addBlur: String {
        switch lang {
        case .en: "Add Blur"
        case .ja: "ぼかしを追加"
        case .hi: "ब्लर जोड़ें"
        case .es: "Añadir desenfoque"
        case .ar: "إضافة ضبابية"
        case .fr: "Ajouter flou"
        case .de: "Unschärfe hinzufügen"
        }
    }

    static var removeBlur: String {
        switch lang {
        case .en: "Remove Blur"
        case .ja: "ぼかしを削除"
        case .hi: "ब्लर हटाएं"
        case .es: "Quitar desenfoque"
        case .ar: "إزالة الضبابية"
        case .fr: "Supprimer flou"
        case .de: "Unschärfe entfernen"
        }
    }

    static var saved: String {
        switch lang {
        case .en: "Saved"
        case .ja: "保存完了"
        case .hi: "सहेजा गया"
        case .es: "Guardado"
        case .ar: "تم الحفظ"
        case .fr: "Enregistré"
        case .de: "Gespeichert"
        }
    }

    static var ok: String {
        "OK"
    }

    static var photoSaved: String {
        switch lang {
        case .en: "Photo saved to your library."
        case .ja: "写真をライブラリに保存しました。"
        case .hi: "फोटो आपकी लाइब्रेरी में सहेजी गई।"
        case .es: "Foto guardada en tu biblioteca."
        case .ar: "تم حفظ الصورة في مكتبتك."
        case .fr: "Photo enregistrée dans votre bibliothèque."
        case .de: "Foto in Ihrer Bibliothek gespeichert."
        }
    }

    /// Result
    static var original: String {
        switch lang {
        case .en: "Original"
        case .ja: "オリジナル"
        case .hi: "मूल"
        case .es: "Original"
        case .ar: "الأصلي"
        case .fr: "Original"
        case .de: "Original"
        }
    }

    static var longPressCompare: String {
        switch lang {
        case .en: "Long press to compare"
        case .ja: "長押しで比較"
        case .hi: "तुलना के लिए लंबे समय तक दबाएं"
        case .es: "Mantén presionado para comparar"
        case .ar: "اضغط مطولاً للمقارنة"
        case .fr: "Appui long pour comparer"
        case .de: "Lange drücken zum Vergleichen"
        }
    }

    static var share: String {
        switch lang {
        case .en: "Share"
        case .ja: "共有"
        case .hi: "शेयर"
        case .es: "Compartir"
        case .ar: "مشاركة"
        case .fr: "Partager"
        case .de: "Teilen"
        }
    }

    static var result: String {
        switch lang {
        case .en: "Result"
        case .ja: "結果"
        case .hi: "परिणाम"
        case .es: "Resultado"
        case .ar: "النتيجة"
        case .fr: "Résultat"
        case .de: "Ergebnis"
        }
    }

    /// Settings
    static var settings: String {
        switch lang {
        case .en: "Settings"
        case .ja: "設定"
        case .hi: "सेटिंग्स"
        case .es: "Ajustes"
        case .ar: "الإعدادات"
        case .fr: "Paramètres"
        case .de: "Einstellungen"
        }
    }

    static var privacyPolicy: String {
        switch lang {
        case .en: "Privacy Policy"
        case .ja: "プライバシーポリシー"
        case .hi: "गोपनीयता नीति"
        case .es: "Política de privacidad"
        case .ar: "سياسة الخصوصية"
        case .fr: "Politique de confidentialité"
        case .de: "Datenschutzrichtlinie"
        }
    }

    static var termsOfUse: String {
        switch lang {
        case .en: "Terms of Use"
        case .ja: "利用規約"
        case .hi: "उपयोग की शर्तें"
        case .es: "Términos de uso"
        case .ar: "شروط الاستخدام"
        case .fr: "Conditions d'utilisation"
        case .de: "Nutzungsbedingungen"
        }
    }

    static var support: String {
        switch lang {
        case .en: "Support"
        case .ja: "サポート"
        case .hi: "सहायता"
        case .es: "Soporte"
        case .ar: "الدعم"
        case .fr: "Assistance"
        case .de: "Support"
        }
    }

    static var version: String {
        switch lang {
        case .en: "Version"
        case .ja: "バージョン"
        case .hi: "संस्करण"
        case .es: "Versión"
        case .ar: "الإصدار"
        case .fr: "Version"
        case .de: "Version"
        }
    }

    static var done: String {
        switch lang {
        case .en: "Done"
        case .ja: "完了"
        case .hi: "पूर्ण"
        case .es: "Listo"
        case .ar: "تم"
        case .fr: "Terminé"
        case .de: "Fertig"
        }
    }

    /// Blur styles
    static var gaussian: String {
        switch lang {
        case .en: "Gaussian"
        case .ja: "ガウス"
        case .hi: "गॉसियन"
        case .es: "Gaussiano"
        case .ar: "ضبابي"
        case .fr: "Gaussien"
        case .de: "Gauß"
        }
    }

    static var bokeh: String {
        switch lang {
        case .en: "Bokeh"
        case .ja: "ボケ"
        case .hi: "बोकेह"
        case .es: "Bokeh"
        case .ar: "بوكيه"
        case .fr: "Bokeh"
        case .de: "Bokeh"
        }
    }

    static var zoom: String {
        switch lang {
        case .en: "Zoom"
        case .ja: "ズーム"
        case .hi: "ज़ूम"
        case .es: "Zoom"
        case .ar: "تكبير"
        case .fr: "Zoom"
        case .de: "Zoom"
        }
    }

    static var motion: String {
        switch lang {
        case .en: "Motion"
        case .ja: "モーション"
        case .hi: "मोशन"
        case .es: "Movimiento"
        case .ar: "حركة"
        case .fr: "Mouvement"
        case .de: "Bewegung"
        }
    }

    static var mosaic: String {
        switch lang {
        case .en: "Mosaic"
        case .ja: "モザイク"
        case .hi: "मोज़ेक"
        case .es: "Mosaico"
        case .ar: "فسيفساء"
        case .fr: "Mosaïque"
        case .de: "Mosaik"
        }
    }

    static var language: String {
        switch lang {
        case .en: "Language"
        case .ja: "言語"
        case .hi: "भाषा"
        case .es: "Idioma"
        case .ar: "اللغة"
        case .fr: "Langue"
        case .de: "Sprache"
        }
    }

    /// IAP
    static var removeAds: String {
        switch lang {
        case .en: "Remove Ads"
        case .ja: "広告を削除"
        case .hi: "विज्ञापन हटाएं"
        case .es: "Eliminar anuncios"
        case .ar: "إزالة الإعلانات"
        case .fr: "Supprimer les pubs"
        case .de: "Werbung entfernen"
        }
    }

    static var restorePurchase: String {
        switch lang {
        case .en: "Restore Purchase"
        case .ja: "購入を復元"
        case .hi: "खरीदारी पुनर्स्थापित करें"
        case .es: "Restaurar compra"
        case .ar: "استعادة الشراء"
        case .fr: "Restaurer l'achat"
        case .de: "Kauf wiederherstellen"
        }
    }

    static var adsRemoved: String {
        switch lang {
        case .en: "Ads Removed"
        case .ja: "広告削除済み"
        case .hi: "विज्ञापन हटाए गए"
        case .es: "Anuncios eliminados"
        case .ar: "تمت إزالة الإعلانات"
        case .fr: "Pubs supprimées"
        case .de: "Werbung entfernt"
        }
    }

    static var saveFailed: String {
        switch lang {
        case .en: "Failed to save photo"
        case .ja: "写真の保存に失敗しました"
        case .hi: "फोटो सहेजने में विफल"
        case .es: "Error al guardar la foto"
        case .ar: "فشل في حفظ الصورة"
        case .fr: "Échec de l'enregistrement"
        case .de: "Foto speichern fehlgeschlagen"
        }
    }

    static var error: String {
        switch lang {
        case .en: "Error"
        case .ja: "エラー"
        case .hi: "त्रुटि"
        case .es: "Error"
        case .ar: "خطأ"
        case .fr: "Erreur"
        case .de: "Fehler"
        }
    }
}
