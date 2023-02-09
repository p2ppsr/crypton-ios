//
//  ReferenceCode.swift
//  Crypton
//
//  Created by Brayden Langley on 2/8/23.
//

//import Foundation

//Task.init {
    // test createAction
//            let result:JSON = await sdk.createAction(
//                outputs: [outputs],
//                description: "iOS Action!"
//            )
//            print(result)
////             Test Create and verify hmac
//            let data = "Some message"
//            let result1 = await sdk.createHmac(data: data, protocolID: PROTOCOL_ID, keyID: KEY_ID)
//            print(result1)
//            let verified = await sdk.verifyHmac(data: data, hmac: result1, protocolID: PROTOCOL_ID, keyID: KEY_ID)
//            print(verified)
//
////             Test create signature and verify
//            let result2 = await sdk.createSignature(data: data, protocolID: PROTOCOL_ID, keyID: KEY_ID)
//            let verified2 = await sdk.verifySignature(data: data, signature: result2, protocolID: PROTOCOL_ID, keyID: KEY_ID)
//            print(verified2)
//
//            let publicKey = await sdk.getPublicKey(protocolID: try! JSON(PROTOCOL_ID), keyID: KEY_ID)
//            print(publicKey)
//
//            let getVersion = await sdk.getVersion()
//            print(getVersion)
//
////             Test Create Certificate
//            let fields:JSON =  [
//                "cool": true
//            ]
////
//            let result3:JSON = await sdk.createCertificate(certificateType: "AGfk/WrT1eBDXpz3mcw386Zww2HmqcIn3uY6x4Af1eo=", fieldObject: fields, certifierUrl: "http://localhost:8080", certifierPublicKey: "04cab461076409998157f05bb90f07886380186fd3d88b99c549f21de4d2511b8388cfd9e557bba8263a1e8b0a293d6696e2ac3e9e9343d6941b4434f7a62156e8")
//            print(result3)
//
////             Test Prove Certificate
//            let certifiers:JSON = ["04cab461076409998157f05bb90f07886380186fd3d88b99c549f21de4d2511b8388cfd9e557bba8263a1e8b0a293d6696e2ac3e9e9343d6941b4434f7a62156e8"]
//            let types:JSON = [
//                "AGfk/WrT1eBDXpz3mcw386Zww2HmqcIn3uY6x4Af1eo=": ["cool"]
//            ]
//
//            let result4:JSON = await sdk.getCertificates(certifiers: certifiers, types: types)
//            print(result4)
//
//            let fieldsToReveal:JSON = ["cool"]
//
//            let certificate:JSON = (result.result?.certificates?[0])!
//            let provableCert:JSON = await sdk.proveCertificate(certificate: certificate, fieldsToReveal: fieldsToReveal, verifierPublicIdentityKey: "042e5bd6b837cfb30208bbb1d571db9ddf2fb1a7b59fb4ed2a31af632699f770a1a1bb8d4a9d332099210ab00b5c1fd0a0c332c8d55f8be0a42906906454c252ed")
//            print(provableCert)
//
//
////             Test submit direct transaction
//            let mockTransaction:JSON = [
//                "mapiResponses": "mock_mapi",
//                "inputs": [ "mock": "inputs"],
//                "rawTx": "mock_rawtx",
//                "outputs": [[
//                  "derivationSuffix": "foo",
//                  "satoshis": 1,
//                  "vout": 0
//                ]]
//            ]
//            let result5:JSON = await sdk.submitDirectTransaction(protocolID: "crypton", transaction: mockTransaction, senderIdentityKey: "042e5bd6b837cfb30208bbb1d571db9ddf2fb1a7b59fb4ed2a31af632699f770a1a1bb8d4a9d332099210ab00b5c1fd0a0c332c8d55f8be0a42906906454c252ed", note: "Test iOS direct transaction submission", amount: 100, derivationPrefix: "global")
//            print(result5)
//
////            Buffer.from(constants.tempoBridge, 'utf8'), // Protocol Namespace Address
////              Buffer.from(song.title, 'utf8'),
////              Buffer.from(song.artist, 'utf8'),
////              Buffer.from('Default description', 'utf8'), // TODO: Add to UI
////              Buffer.from('' + duration, 'utf8'), // Duration
////              Buffer.from(songURL, 'utf8'),
////              Buffer.from(artworkFileURL, 'utf8')
//
////             Push Drop Create Test
//            let fields2:JSON = [
//                "protocol namespace address",
//                "songtitle",
//                "songartist",
//                "description",
//                "duration",
//                "songurl",
//                "artworkfileURL"
//            ]
//
//            let result6:String = await sdk.createPushDropScript(fields: fields2, protocolID: "Tempo", keyID: "1")
//            print(result6)
//
////             Test Parapet-JS
////            let query:JSON = [
////              "v": 3,
////              "q": [
////                "collection": "songs",
////                "find": ["artist": "Brayden Langley"]
////              ]
////            ]
////            let resolvers:JSON = ["https://staging-bridgeport.babbage.systems"]
////            let result = await sdk.parapetJSONQuery(resolvers: resolvers, bridge: "1LQtKKK7c1TN3UcRfsp8SqGjWtzGskze36", type: "json-query", query: query)
////            print(result)
////
////            print(sdk.generateRandomBase64String(byteCount: 64))
//
//            // Test Authrite Request
//            let params:JSON = []
//            let fetchConfig:JSON = [
//                "body": [
//                    "songURL":"XUUnYfCdpxjX9zy7unkpdrVaVRLmJwA3ygBEWNN39n4uk5WnsEWT",
//                ],
//                "method":"POST",
//                "headers": [
//                    "Content-Type": "application/json"
//                ]
//            ] //.base64EncodedString()
//            let invoice:JSON = await sdk.newAuthriteRequest(params: params, requestUrl: "https://staging-tempo-keyserver.babbage.systems/invoice", fetchConfig: fetchConfig)
////            print(invoice)
////
////            // Test key derivation and output script generation
//            let derivationPrefix = try! sdk.generateSecureRandomBase64String(byteCount: 10)
//            let derivationSuffix = try! sdk.generateSecureRandomBase64String(byteCount: 10)
//            let protocolID:JSON = [2, "3241645161d8"]
//            let derivedPublicKey = await sdk.getPublicKey(protocolID: protocolID, keyID: "\(derivationPrefix) \(derivationSuffix)", counterparty: invoice.result!.identityKey!.stringValue)
//            print(derivedPublicKey)
////
//            let script = await sdk.createOutputScriptFromPubKey(derivedPublicKey: derivedPublicKey)
//            print(script)
//
//            let outputs:JSON = [[
//                "script": try! JSON(script),
//                "satoshis": 100
//            ]]
//
//            let payment = await sdk.createAction(outputs: outputs, description: "payment for song")
//            print(payment)
//
//
//            let fetchConfig2:JSON = [
//                "body": [
//                    "derivationPrefix": try! JSON(derivationPrefix),
//                    "songURL": "XUUnYfCdpxjX9zy7unkpdrVaVRLmJwA3ygBEWNN39n4uk5WnsEWT",
//                    "transaction": [
//                        "mapiResponses": payment.result!.mapiResponses!,
//                        "txid": payment.result!.txid!,
//                        "rawTx": payment.result!.rawTx!,
//                        "inputs": payment.result!.inputs!,
//                        "outputs": [[
//                            "vout": 0,
//                            "satoshis": 100,
//                            "derivationSuffix": try! JSON(derivationSuffix)
//                        ]]
//                    ],
//                    "orderID": invoice.result!.orderID!
//                ],
//                "method":"POST",
//                "headers": [
//                    "Content-Type": "application/json"
//                ]
//            ] //.base64EncodedString()
//            let paymentResult:JSON = await sdk.newAuthriteRequest(params: params, requestUrl: "https://staging-tempo-keyserver.babbage.systems/pay", fetchConfig: fetchConfig2)
//            let decryptionKey:String = paymentResult.result!.result!.stringValue!
//            print(decryptionKey)


    // Test cryptokey
//            let result2 = await sdk.generateAES256GCMCryptoKey()
//    let result2 = "fMx3ukLaavhWCacif6N0j68SAKE5U2KoV940v+JK7K0="
//    let result3 = await sdk.encryptUsingCryptoKey(plaintext: "Test message", base64CryptoKey: result2, returnType: "base64")
//    print(result3)
    ////////////////////////////
//            let decryptionKey = "emYWwAocGIzy9BUinm9Tmf2gEnSFkkVXQbfJgmBIvBg=" // TODO: Add error handling
//
//
//            // Test NanoSeek file download
//            let bridgeportResolvers:JSON = ["https://staging-bridgeport.babbage.systems"]
//            let result7:Data = await sdk.downloadUHRPFile(URL: "XUUnYfCdpxjX9zy7unkpdrVaVRLmJwA3ygBEWNN39n4uk5WnsEWT", bridgeportResolvers: bridgeportResolvers)!
////            print(result[0])
//
//    let plaintext:String = await sdk.decryptUsingCryptoKey(ciphertext: result3, base64CryptoKey: result2)
//    let decryptedData = Data(base64Encoded: plaintext)
//    print(plaintext)
//
//            let audioData = Data.init(base64Encoded: plaintext)
//               do
//               {
//                   try audioPlayer = .init(data: audioData!)
//                   audioPlayer?.delegate = self as? AVAudioPlayerDelegate
//                   audioPlayer?.prepareToPlay()
//                   audioPlayer?.play()
//
//               } catch {
//                   print("An error occurred while trying to extract audio file")
//               }
    ////////////////////////////
//            print(bytes)
//            print(bytes.count)

//            await new Authrite().request(`${constants.keyServerURL}/publish`, {
//                body: {
//                  songURL,
//                  key: Buffer.from(decryptionKey).toString('base64')
//                },
//                method: 'POST',
//                headers: {
//                  'Content-Type': 'application/json'
//                }
//              })
