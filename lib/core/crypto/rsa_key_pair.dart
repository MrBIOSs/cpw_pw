typedef RsaKeyPair = ({
BigInt modulus,           // n = p * q
BigInt publicExponent,    // e (usually 65537)
BigInt privateExponent,   // d
String privateKeyPem,     // PEM string for storage/transmission
String publicKeyPem,      // PEM string for distribution
});