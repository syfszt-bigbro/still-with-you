import Foundation

extension AppModel {
  func pauseReply(paused: Bool) -> String {
    let banks: [String: ([String], [String])] = [
      "zh": (["暂停好啦，歇一会儿，我在。", "先停一下，准备好了再继续。", "计时停住啦，不着急。"], ["继续啦，咱们接着来。", "计时继续了，一次专心做一件事。", "回来啦，接着刚才的节奏走。"]),
      "en": (["Paused. Take a breather; I'm here.", "Timer paused. Continue when you're ready."], ["Resumed. Let's keep going.", "The timer is running again. One thing at a time."]),
      "ja": (["一時停止したよ。ひと息つこう。", "タイマーを止めたよ。準備ができたら続けよう。"], ["再開したよ。一緒に続けよう。", "タイマーがまた動き始めたよ。ひとつずつね。"]),
      "ko": (["일시 정지했어요. 잠깐 쉬어요.", "타이머를 멈췄어요. 준비되면 계속해요."], ["다시 시작했어요. 이어서 해봐요.", "타이머가 다시 움직여요. 하나씩 해요."]),
      "fr": (["C’est en pause. Souffle un peu.", "Minuteur arrêté. Reprends quand tu es prêt."], ["C’est reparti. On continue.", "Le minuteur tourne à nouveau. Une chose à la fois."]),
      "ru": (["Пауза. Немного отдохни.", "Таймер остановлен. Продолжим, когда будешь готов."], ["Продолжаем. Я рядом.", "Таймер снова идёт. По одному делу за раз."]),
      "pt": (["Em pausa. Descansa um pouco.", "Temporizador pausado. Continua quando quiseres."], ["Retomado. Vamos continuar.", "O temporizador voltou a contar. Uma coisa de cada vez."]),
      "es": (["En pausa. Descansa un momento.", "Temporizador pausado. Sigue cuando quieras."], ["Reanudado. Sigamos.", "El temporizador sigue contando. Una cosa a la vez."]),
      "ar": (["تم الإيقاف مؤقتًا. خذ استراحة قصيرة.", "المؤقت متوقف. تابع عندما تكون مستعدًا."], ["تم الاستئناف. لنكمل معًا.", "المؤقت يعمل مجددًا. خطوة واحدة كل مرة."])
    ]
    let pair = banks[voiceLanguage.rawValue] ?? banks["en"]!
    let phrase = say(paused ? "pause" : "resume", (paused ? pair.0 : pair.1).randomElement()!)
    guard let timer = state.timer else { return "\(userName)，\(phrase)" }
    let remaining = voiceLanguage.rawValue == "en" ? "remaining \(clock)" : "还剩 \(clock)"
    if timer.phase == .exercise {
      let activity = activeTask?.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
      let label = (activity?.isEmpty == false) ? activity! : "运动"
      switch voiceLanguage.rawValue {
      case "zh": return "\(userName)，\(phrase)\n「\(label)」\(paused ? "先歇一下" : "继续活动")，\(remaining)。"
      case "en": return "\(userName), \(phrase)\nExercise: \(label). \(remaining)."
      default: return "\(userName)，\(phrase)\n\(timer.phase.title)：\(label)，\(remaining)。"
      }
    }
    return "\(userName)，\(phrase)\n「\(activeTask?.title ?? "")」 · \(remaining)"
  }
}
