#!/usr/bin/env node
import crypto from "node:crypto";

const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");

const privateDer = privateKey.export({ format: "der", type: "pkcs8" });
const publicDer = publicKey.export({ format: "der", type: "spki" });
const rawPublicKey = publicDer.subarray(publicDer.length - 32);

console.log("Add this to .env and keep it secret:");
console.log(`DACX_UPDATE_PRIVATE_KEY_PKCS8_BASE64=${privateDer.toString("base64")}`);
console.log("");
console.log("Commit this public key in lib/services/update_trust_config.dart:");
console.log(`windowsManifestPublicKeyBase64 = '${rawPublicKey.toString("base64")}'`);
