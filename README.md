# crypton-ios
 Babbage Message Encryption and Decryption iOS App

## Introduction
The purpose of this app is to illustrate how simple it can be to start building apps using the [Babbage SDK for iOS](https://github.com/p2ppsr/babbage-sdk-ios).

With Crypton, you can generate encrypted QR codes that only you and your friends can decode. It's easy to get started - simply sign up for an account and get your identity key. Then, share your identity key QR code with your friends and let them scan it to add your public key to their contacts.

Once you and your friends have added each other's public keys to your contacts, you can exchange secure messages by creating encrypted QR codes that only you and your friend can read. To do this, your friend writes you a secret message, then generates a secret QR code using the "new message" button. You can then scan the secret QR code using the "decrypt QR code" button and your friend's public key in your contacts to reveal the secret message.

## Features
* Securely log in with your Babbage Identity which is shared across all applications.
* View your MetaNet portal containing your actions, permissions granted, and more.
* Encrypt messages using secure keys derived from your identity key specifically for the Crypton protocol.
* Securely decrypt messages that only you can decrypt.
* You can even encrypt encrypted messages adding several layers of security!

![](./readme-support/CryptonViews.png)

Available now - [Crypton for iOS](https://apps.apple.com/us/app/crypton-secure-qr-generator/id1671880722)!
