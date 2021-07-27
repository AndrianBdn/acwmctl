import Foundation;

typealias CommandDict = Dictionary<String, Any>

struct Config : Decodable {
    let ip : String
    let username: String
    let password: String
    
    var dataJsonUrl : URL {
        return URL(string: "http://\(ip)/js/data/data.json")!
    }
    
    var commandUrl : URL {
        return URL(string: "http://\(ip)/api.cgi")!
    }
    
    static var configURL : URL {
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".acwm")
    }
    
    static func load() throws -> Config  {
        let decoder = JSONDecoder()
        let data = try Data.init(contentsOf: Config.configURL)
        return try decoder.decode(Config.self, from: data)
    }
}

do {
    let config = try Config.load()
    let acwm = ACWM(config: config)
    acwm.runCommand(args: CommandLine.arguments)
    
} catch {
    print("Error loading config \(Config.configURL): \(error)")
}

struct ACWM {
    let config : Config
    let session = URLSession(configuration: .ephemeral)
    
    enum Uid: Int {
        case onOff = 1
        case fanLevel = 4
    }
    
    func runCommand(args: [String]) {
        
        func usageDie() {
            print("Usage: \(args[0]) <on|off|fan 1-4>")
            exit(1)
        }
        
        if args.count <= 1 {
            usageDie()
        }

        let cmd = args[1]
        
        switch (cmd) {
        case "on":
            execute(uid: Uid.onOff, value: 1)
        case "off":
            execute(uid: Uid.onOff, value: 0)
        case "fan":
            if args.count < 2 {
                print("error: set fan level")
                exit(1)
            }
            let lvl = Int(args[2]) ?? 0
            if lvl < 1 || lvl > 4 {
                print("error fan level must be in range 1...4")
                exit(1)
            }
            
            execute(uid: Uid.fanLevel, value: lvl)
            
        default:
            usageDie()
        }
        
    }
    
    func execute(uid: Uid, value: Int) {
        initAc { success in
            if (!success) {
                print("there were errors during init process")
                exit(1)
            }

            login { sessionId in
                guard let sessionId = sessionId else {
                    print("unable to auth, bad sessionId")
                    exit(1)
                }
                setdatapointvalue(sessionId: sessionId, uid: uid, value: value) { result in
                    print("setdatapointvalue \(uid)=\(value): \(result ? "success" : "fail")")
                    logout(sessionId: sessionId)
                }
                
            }
        }
        
        RunLoop.main.run()
    }
    
    
    func initAc(completionHandler: @escaping (Bool) -> Void) {
        let request = URLRequest(url: config.dataJsonUrl)
        let task = session.dataTask(with: request) { data, response, err in
            
            guard let data = data else {
                if let error = err {
                    print("error executing request to \(config.dataJsonUrl): \(error)")
                }
                completionHandler(false)
                return
            }
            
            struct Response: Decodable {
                var signals: Signals
                
                struct Signals: Decodable {
                    var uid: Dictionary<String, [UidValue]>
                    var uidTextvalues: Dictionary<String, Dictionary<String, String>>
                }
                
                enum UidValue: Decodable {
                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if let x = try? container.decode(String.self) {
                            self = .string(x)
                        }
                        else if let x = try? container.decode(Dictionary<String, String>.self) {
                            self = .dictinary(x)
                        }
                        else {
                            throw DecodingError.typeMismatch(UidValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for UidValue"))
                        }
                    }
                    
                    case string(String)
                    case dictinary(Dictionary<String, String>)
                }
            }
            
            let decoder = JSONDecoder()
            let response = try! decoder.decode(Response.self, from: data)
            
            let checker = [
                "\(Uid.onOff.rawValue)" : "On/Off",
                "\(Uid.fanLevel.rawValue)" : "Fan Speed"
            ]
            
            for (key, value) in checker {
                
                guard let apiUidArray = response.signals.uid[key] else {
                    print("unable to find \(key) in signals.uid")
                    completionHandler(false)
                    return
                }
                
                if apiUidArray.count < 1 {
                    print("bad value for \(key) in signals.uid \(apiUidArray)")
                    completionHandler(false)
                    return
                }
                
                if case .string(let str) = apiUidArray[0] {
                    if (str != value) {
                        print("booting fail, key \(key) expected \(value) found \(str)")
                        completionHandler(false)
                        return
                    }
                }
            }
            
            
            completionHandler(true)
        }
        task.resume()
    }

    func write(command: String, dict: CommandDict, completionHandler: @escaping (Dictionary<String, Any>?, Error?) -> Void)  {
        var request = URLRequest(url: config.commandUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: ["command": command, "data": dict])
        
        let task = session.dataTask(with: request) { data, response, err in
            if let err = err {
                completionHandler(nil, err)
                return
            }
            guard let data = data else {
                completionHandler(nil, NSError(domain: "my", code: 1, userInfo: nil))
                return
            }
            
            guard let dict = try? JSONSerialization.jsonObject(with: data) as? Dictionary<String, Any>
            else {
                return
            }
            
            completionHandler(dict, nil);
        }
        task.resume()
    }
    
    func login(completionHandler: @escaping (String?) -> Void) {
        write(command: "login", dict: ["username": config.username, "password": config.password]) {
            dict,err in

            guard let dict = dict else {
                completionHandler(nil)
                return
            }

            let data = dict["data"] as? Dictionary<String, Any>
            let id = data?["id"] as? Dictionary<String, Any>
            let sessionId = id?["sessionID"] as? String;

            completionHandler(sessionId)
        }
    }
    
    func setdatapointvalue(sessionId: String, uid: Uid, value: Int, completionHandler: @escaping (Bool) -> Void) {

        let dict : CommandDict = ["sessionID": sessionId, "uid": uid.rawValue, "value": value]

        write(command: "setdatapointvalue", dict: dict) { dict, err in
            if let dict = dict {
                completionHandler((dict["success"] as? Int ?? 0) > 0)
                return
            }
            completionHandler(false)
        }
    }
    
    func logout(sessionId: String) {
        write(command: "logout", dict: ["sessionID": sessionId]) {_,_ in
            exit(0)
        }
    }
    
}
