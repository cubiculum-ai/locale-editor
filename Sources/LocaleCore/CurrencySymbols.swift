// Generated from Unicode 18.0.0 UnicodeData.txt, General_Category=Sc.
// Source: https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt
// Copyright Unicode, Inc. See ThirdParty/UNICODE-LICENSE.txt.
import Foundation

public struct CurrencySymbol: Sendable, Identifiable {
    public let scalar: UInt32
    public let name: String
    public var symbol: String { String(UnicodeScalar(scalar)!) }
    public var id: String { String(format: "U+%04X", scalar) }
}

public enum CurrencySymbols {
    public static let unicodeVersion = "18.0.0"
    public static let all: [CurrencySymbol] = [
        .init(scalar: 0x0024, name: "DOLLAR SIGN"),
        .init(scalar: 0x00A2, name: "CENT SIGN"),
        .init(scalar: 0x00A3, name: "POUND SIGN"),
        .init(scalar: 0x00A4, name: "CURRENCY SIGN"),
        .init(scalar: 0x00A5, name: "YEN SIGN"),
        .init(scalar: 0x058F, name: "ARMENIAN DRAM SIGN"),
        .init(scalar: 0x060B, name: "AFGHANI SIGN"),
        .init(scalar: 0x07FE, name: "NKO DOROME SIGN"),
        .init(scalar: 0x07FF, name: "NKO TAMAN SIGN"),
        .init(scalar: 0x09F2, name: "BENGALI RUPEE MARK"),
        .init(scalar: 0x09F3, name: "BENGALI RUPEE SIGN"),
        .init(scalar: 0x09FB, name: "BENGALI GANDA MARK"),
        .init(scalar: 0x0AF1, name: "GUJARATI RUPEE SIGN"),
        .init(scalar: 0x0BF9, name: "TAMIL RUPEE SIGN"),
        .init(scalar: 0x0E3F, name: "THAI CURRENCY SYMBOL BAHT"),
        .init(scalar: 0x17DB, name: "KHMER CURRENCY SYMBOL RIEL"),
        .init(scalar: 0x20A0, name: "EURO-CURRENCY SIGN"),
        .init(scalar: 0x20A1, name: "COLON SIGN"),
        .init(scalar: 0x20A2, name: "CRUZEIRO SIGN"),
        .init(scalar: 0x20A3, name: "FRENCH FRANC SIGN"),
        .init(scalar: 0x20A4, name: "LIRA SIGN"),
        .init(scalar: 0x20A5, name: "MILL SIGN"),
        .init(scalar: 0x20A6, name: "NAIRA SIGN"),
        .init(scalar: 0x20A7, name: "PESETA SIGN"),
        .init(scalar: 0x20A8, name: "RUPEE SIGN"),
        .init(scalar: 0x20A9, name: "WON SIGN"),
        .init(scalar: 0x20AA, name: "NEW SHEQEL SIGN"),
        .init(scalar: 0x20AB, name: "DONG SIGN"),
        .init(scalar: 0x20AC, name: "EURO SIGN"),
        .init(scalar: 0x20AD, name: "KIP SIGN"),
        .init(scalar: 0x20AE, name: "TUGRIK SIGN"),
        .init(scalar: 0x20AF, name: "DRACHMA SIGN"),
        .init(scalar: 0x20B0, name: "GERMAN PENNY SIGN"),
        .init(scalar: 0x20B1, name: "PESO SIGN"),
        .init(scalar: 0x20B2, name: "GUARANI SIGN"),
        .init(scalar: 0x20B3, name: "AUSTRAL SIGN"),
        .init(scalar: 0x20B4, name: "HRYVNIA SIGN"),
        .init(scalar: 0x20B5, name: "CEDI SIGN"),
        .init(scalar: 0x20B6, name: "LIVRE TOURNOIS SIGN"),
        .init(scalar: 0x20B7, name: "SPESMILO SIGN"),
        .init(scalar: 0x20B8, name: "TENGE SIGN"),
        .init(scalar: 0x20B9, name: "INDIAN RUPEE SIGN"),
        .init(scalar: 0x20BA, name: "TURKISH LIRA SIGN"),
        .init(scalar: 0x20BB, name: "NORDIC MARK SIGN"),
        .init(scalar: 0x20BC, name: "MANAT SIGN"),
        .init(scalar: 0x20BD, name: "RUBLE SIGN"),
        .init(scalar: 0x20BE, name: "LARI SIGN"),
        .init(scalar: 0x20BF, name: "BITCOIN SIGN"),
        .init(scalar: 0x20C0, name: "SOM SIGN"),
        .init(scalar: 0x20C1, name: "SAUDI RIYAL SIGN"),
        .init(scalar: 0x20C2, name: "RUFIYAA SIGN"),
        .init(scalar: 0x20C3, name: "UAE DIRHAM SIGN"),
        .init(scalar: 0x20C4, name: "OMANI RIAL SIGN"),
        .init(scalar: 0xA838, name: "NORTH INDIC RUPEE MARK"),
        .init(scalar: 0xFDFC, name: "RIAL SIGN"),
        .init(scalar: 0xFE69, name: "SMALL DOLLAR SIGN"),
        .init(scalar: 0xFF04, name: "FULLWIDTH DOLLAR SIGN"),
        .init(scalar: 0xFFE0, name: "FULLWIDTH CENT SIGN"),
        .init(scalar: 0xFFE1, name: "FULLWIDTH POUND SIGN"),
        .init(scalar: 0xFFE5, name: "FULLWIDTH YEN SIGN"),
        .init(scalar: 0xFFE6, name: "FULLWIDTH WON SIGN"),
        .init(scalar: 0x11FDD, name: "TAMIL SIGN KAACU"),
        .init(scalar: 0x11FDE, name: "TAMIL SIGN PANAM"),
        .init(scalar: 0x11FDF, name: "TAMIL SIGN PON"),
        .init(scalar: 0x11FE0, name: "TAMIL SIGN VARAAKAN"),
        .init(scalar: 0x1E2FF, name: "WANCHO NGUN SIGN"),
        .init(scalar: 0x1ECB0, name: "INDIC SIYAQ RUPEE MARK"),
    ]
}

public extension CurrencySymbols {
    static let license = """
    UNICODE LICENSE V3
    
    COPYRIGHT AND PERMISSION NOTICE
    
    Copyright © 1991-2026 Unicode, Inc.
    
    NOTICE TO USER: Carefully read the following legal agreement. BY
    DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
    SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
    TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
    DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
    
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of data files and any associated documentation (the "Data Files") or
    software and any associated documentation (the "Software") to deal in the
    Data Files or Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, and/or sell
    copies of the Data Files or Software, and to permit persons to whom the
    Data Files or Software are furnished to do so, provided that either (a)
    this copyright and permission notice appear with all copies of the Data
    Files or Software, or (b) this copyright and permission notice appear in
    associated Documentation.
    
    THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
    KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
    THIRD PARTY RIGHTS.
    
    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
    BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
    OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
    WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
    ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
    FILES OR SOFTWARE.
    
    Except as contained in this notice, the name of a copyright holder shall
    not be used in advertising or otherwise to promote the sale, use or other
    dealings in these Data Files or Software without prior written
    authorization of the copyright holder.
    """
}
