//
//  ApiService.swift
//  MySwiftUI-MVVM
//
//  Created by Wisanu Paunglumjeak on 7/10/2563 BE.
//

import Foundation
import Alamofire
import Combine

class ApiService<T: Codable> {
    private init(){
        
    }
    
    static var shared: ApiService<T> {
        get{
            return ApiService<T>()
        }
    }
    
    func renewToken() -> AnyPublisher<Void, APIError>{
        let service = Service.renewAccessToken.serviceConfig
        let refreshToken = UserDefaults.standard.string(forKey: PreferenceKeys.refreshToken) ?? ""
        let headers = [
            "Content-Type": service.contentType.rawValue
        ]
        
        let authen = Authenticate()
        authen.refreshToken = refreshToken
        let genericRequest = GenericRequest.init(authen)
        
        return AF.request(service.serviceUrl,
                          method: service.method,
                          parameters: Utils.Objects.encode(from: genericRequest),
                          encoding: JSONEncoding.default,
                          headers: HTTPHeaders(headers))
            .publishDecodable(type: GenericResponse<Authenticate>.self)
            .filter({ (dataResponse) -> Bool in
                guard let statusCode = dataResponse.response?.statusCode else {
                    return false
                }
                
                return 200..<300 ~= statusCode
            })
            .mapError{ _ in APIError.none }
            .flatMap({ (dataResponse) -> AnyPublisher<Void, APIError> in
                if let response = dataResponse.value,
                   let authenResponse = response.result {
                    UserDefaults.standard.set(authenResponse.accessToken, forKey: PreferenceKeys.accessToken)
                    UserDefaults.standard.set(authenResponse.refreshToken, forKey: PreferenceKeys.refreshToken)
                }
                
                return Just(()).mapError{ _ in APIError.none }.eraseToAnyPublisher()
            }).receive(on: RunLoop.main).eraseToAnyPublisher()
    }
    
    func service(_ service: Service,
                 params: Parameters?) -> AnyPublisher<GenericResponse<T>?, APIError>{
        
        let accessToken = UserDefaults.standard.string(forKey: PreferenceKeys.accessToken) ?? ""
        let serviceConfig = service.serviceConfig
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(accessToken)",
            "Content-Type": serviceConfig.contentType.rawValue
        ]
        
        return self.service(service, params: params, headers: headers)
    }
    
    func serviceWithoutAccess(_ service: Service, params: Parameters?) -> AnyPublisher<GenericResponse<T>?, APIError>{
        
        let serviceConfig = service.serviceConfig
        let headers: HTTPHeaders = ["Content-Type": serviceConfig.contentType.rawValue]
        
        return self.service(service, params: params, headers: headers)
    }
    
    
    func service(_ service: Service,
                 params: Parameters?,
                 headers: HTTPHeaders) -> AnyPublisher<GenericResponse<T>?, APIError>{
        
        let url = service.serviceConfig.serviceUrl
        let method = service.serviceConfig.method
        var encode: ParameterEncoding {
            switch service.serviceConfig.contentType {
            case .json:
                return JSONEncoding.default
            default:
                return URLEncoding.default
            }
        }
        
        return AF.request(url, method: method, parameters: params, encoding: encode, headers: headers)
            .publishDecodable(type: GenericResponse<T>.self)
            .flatMap({ (dataResponse) -> AnyPublisher<GenericResponse<T>?, APIError> in
                guard let genericResponse = dataResponse.value,
                      let statusCode = dataResponse.response?.statusCode else {
                    return Fail(error: APIError.network).eraseToAnyPublisher()
                }
                
                guard 401 != statusCode else {
                    return self.renewToken().flatMap { (response) -> AnyPublisher<GenericResponse<T>?, APIError> in
                        return self.service(service, params: params, headers: headers)
                    }.eraseToAnyPublisher()
                }
                
                guard 200..<300 ~= statusCode else {
                    return Fail(error: APIError.custom(statusCode, genericResponse.message)).eraseToAnyPublisher()
                }
                
                return Just(dataResponse.value).mapError{ _ in APIError.none }.eraseToAnyPublisher()
            }).receive(on: RunLoop.main).eraseToAnyPublisher()
    }
}
