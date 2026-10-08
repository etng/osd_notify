import Foundation

func fetchText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    if let text = String(data: data, encoding: .utf8) {
        return text
    }
    return String(decoding: data, as: UTF8.self)
}

struct HTTPDataResult {
    let statusCode: Int
    let data: Data
}

final class HTTPDataResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var response: URLResponse?
    private var error: Error?

    func set(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        self.data = data
        self.response = response
        self.error = error
        lock.unlock()
    }

    func get() -> (data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (data, response, error)
    }
}

func fetchHTTPData(from url: URL, accept: String) throws -> HTTPDataResult {
    var request = URLRequest(url: url)
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("osd-notify/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 20.0

    let semaphore = DispatchSemaphore(value: 0)
    let box = HTTPDataResultBox()

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        box.set(data: data, response: response, error: error)
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    let result = box.get()
    let dataResult = result.data
    let responseResult = result.response
    let errorResult = result.error
    if let errorResult {
        throw errorResult
    }
    guard let dataResult,
          let httpResponse = responseResult as? HTTPURLResponse else {
        throw CLIError.message("没有收到 HTTP 响应：\(url.absoluteString)")
    }
    return HTTPDataResult(statusCode: httpResponse.statusCode, data: dataResult)
}
