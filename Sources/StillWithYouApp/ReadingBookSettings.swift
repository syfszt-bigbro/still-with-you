import Foundation
import SwiftUI
import StillWithYouCore

private struct BookSearchItem: Identifiable, Sendable {
  var id: String
  var provider: String
  var title: String
  var author: String
  var description: String
  var link: URL?
  var insights: [String] = []
}

private enum BookSearchClient {
  private struct ModelSearch: Decodable {
    struct Book: Decodable {
      var title: String
      var author: String
      var summary: String
      var insights: [String]
    }
    var books: [Book]
  }
  static func search(_ query: String, model: String, key: String, endpoint: URL) async throws -> (items: [BookSearchItem], tokens: Int) {
    let reply = try await AIClient.complete(model: model, key: key, endpoint: endpoint, messages: [
      ["role": "system", "content": "你是书目与阅读助手。根据用户给出的书名、作者或关键词，从你确实掌握的知识中检索相关书籍，并用中文返回严格 JSON：{\"books\":[{\"title\":\"书名\",\"author\":\"作者\",\"summary\":\"50至120字的可靠内容简介\",\"insights\":[\"核心观点转述一\",\"核心观点转述二\",\"核心观点转述三\"]}]}。最多返回5本，优先精确匹配；只有你有把握的书才返回。若书名、作者、内容无法确认，返回空数组。观点必须是概括转述，不得伪造原文、金句、章节、情节或出版信息。不要声称刚刚浏览了网页。书名查询没有歧义时只返回最匹配的一本。每条观点15至42个汉字。"] ,
      ["role": "user", "content": "请在你已知资料中检索与这个查询匹配的真实书籍，并提供作者、简介和观点：\(query)"]
    ], maxTokens: 1100)
    let raw = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start <= end,
      let data = String(raw[start...end]).data(using: .utf8),
      let decoded = try? JSONDecoder().decode(ModelSearch.self, from: data) else {
      throw BookSearchError.invalidResponse
    }
    let items = decoded.books.prefix(5).compactMap { book -> BookSearchItem? in
      let title = String(book.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
      let author = String(book.author.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
      let summary = String(book.summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(700))
      let insights = Array(book.insights.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(70)) }
        .filter { !$0.isEmpty }.prefix(3))
      guard !title.isEmpty, !author.isEmpty, !summary.isEmpty, !insights.isEmpty else { return nil }
      return BookSearchItem(id: title + "|" + author, provider: "AI", title: title,
        author: author, description: summary, link: nil, insights: insights)
    }
    guard !items.isEmpty else { throw BookSearchError.noResults }
    return (items, reply.tokens)
  }

}

private enum BookSearchError: LocalizedError {
  case noResults
  case invalidResponse
  var errorDescription: String? {
    switch self {
    case .noResults: "AI 没找到有把握的匹配书目；试试补充作者名或更完整的书名。"
    case .invalidResponse: "AI 返回的书目格式无法读取，请重试。"
    }
  }
}

struct ReadingBookSettings: View {
  @ObservedObject var model: AppModel
  @State private var query = ""
  @State private var results: [BookSearchItem] = []
  @State private var searching = false
  @State private var status = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("书籍灵感播报").font(.subheadline.weight(.semibold))
      HStack {
        TextField("输入书名，例如《原子习惯》", text: $query).textFieldStyle(.roundedBorder)
          .onSubmit { searchBooks() }
        Button(searching ? "正在搜索…" : "搜索") { searchBooks() }
          .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Text("直接请所选 AI 按书名或作者整理核心观点。使用模型已有知识，不是实时网页搜索；观点是转述，不会伪装成原书金句。")
        .font(.caption).foregroundStyle(.secondary)

      if !model.apiReady {
        Text("请先在下方配置并启用 AI API，才能生成书籍观点。")
          .font(.caption).foregroundStyle(.secondary)
      }
      if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }

      if !results.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(results) { book in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline) {
                Text(book.title).font(.callout.weight(.medium))
                Text(book.author).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("加入书单并播报") { add(book) }
                  .disabled(!model.apiReady)
              }
              Text(book.description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
              if let link = book.link {
                Link("\(book.provider) 书目", destination: link).font(.caption2)
              } else {
                Text("来源：\(book.provider) 已有知识（非网页检索）").font(.caption2).foregroundStyle(.secondary)
              }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
          }
        }
      }

      if !(model.state.preferences.readingBookShelf ?? []).isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("我的书单（\(model.state.preferences.readingBookShelf?.count ?? 0)）")
            .font(.callout.weight(.semibold))
          ForEach(model.state.preferences.readingBookShelf ?? []) { book in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(book.title).font(.callout.weight(.medium))
                  Text(book.author).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.state.preferences.readingBookTitle == book.title {
                  Text("正在播报").font(.caption).foregroundStyle(.secondary)
                } else {
                  Button("用于播报") {
                    model.state.preferences.readingBookTitle = book.title
                    model.state.preferences.readingBookAuthor = book.author
                    model.state.preferences.readingBookInsights = book.insights
                    model.save(); status = "已切换播报书籍。"
                  }
                }
                Button("移除") {
                  model.state.preferences.readingBookShelf?.removeAll { $0.id == book.id }
                  if model.state.preferences.readingBookTitle == book.title {
                    model.state.preferences.readingBookTitle = nil
                    model.state.preferences.readingBookAuthor = nil
                    model.state.preferences.readingBookInsights = nil
                  }
                  model.save(); status = "已从书单移除。"
                }
              }
              ForEach(Array(book.insights.enumerated()), id: \.offset) { _, insight in
                Text(insight)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
          }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.lake.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      } else if let title = model.state.preferences.readingBookTitle,
        let author = model.state.preferences.readingBookAuthor,
        let insights = model.state.preferences.readingBookInsights, !insights.isEmpty {
        // Migrate the previously supported single broadcast book into the new shelf.
        Text("当前播报：《\(title)》· \(author)")
          .onAppear {
            model.state.preferences.readingBookShelf = [SavedReadingBook(title: title, author: author, insights: insights)]
            model.save()
          }
      }
    }.padding(.vertical, 5)
  }

  private func searchBooks() {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    searching = true; status = "正在搜索书目…"
    Task {
      do {
        let found = try await BookSearchClient.search(
          text, model: model.state.preferences.model, key: Secrets.get("chat-api"),
          endpoint: model.state.preferences.resolvedAIEndpoint)
        results = found.items
        model.state.aiRequests += 1; model.state.aiTokens += found.tokens; model.save()
        status = "AI 找到 \(found.items.count) 个候选；请核对书名和作者后加入。"
      } catch {
        results = []; status = error.localizedDescription
      }
      searching = false
    }
  }

  private func add(_ book: BookSearchItem) {
    guard model.apiReady else { status = "请先配置 AI API。"; return }
    model.state.preferences.readingBookTitle = book.title
    model.state.preferences.readingBookAuthor = book.author
    model.state.preferences.readingBookInsights = book.insights
    var shelf = model.state.preferences.readingBookShelf ?? []
    shelf.removeAll { $0.title == book.title && $0.author == book.author }
    shelf.insert(SavedReadingBook(title: book.title, author: book.author, insights: book.insights), at: 0)
    model.state.preferences.readingBookShelf = shelf
    model.save()
    status = "已加入播报；每次主动陪伴时会轮换一句。"
  }
}
