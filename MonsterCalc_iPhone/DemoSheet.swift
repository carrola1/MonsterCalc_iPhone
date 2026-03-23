import Foundation

enum DemoSheet {
    static let text = """
    # vars
    x = 300
    y = 10k
    x * 2
    ans + 5

    # refs
    line2 + line4

    # math
    sqrt(81)
    log2(16)

    # convert
    70 F to C

    # prog
    bin(5, 8)
    0xFF & 0x0E
    bitget(0xFF, 1, 0)

    # ee (voltage divider)
    vdiv(5, 10k, 10k)
    """

    static let eeText = """
    # ee (divider)
    vdiv(5, 10k, 10k)
    findrdiv(5, 3.3, 1)

    # ohm's
    findi(5, 10k)
    findr(3.3, 20m)

    # ac
    xc(1k, 0.1u)
    xl(1k, 10m)

    # rc
    fc_rc(10k, 0.1u)
    tau(10k, 0.1u)
    """

    static let progText = """
    # prog
    0xFF & 0x0E
    0b1010 << 2
    bin(5, 8)
    hex(0b11010110)

    # bits
    bitget(0xFF, 3, 0)
    bitset(0x01, 7, 1)

    # text
    a2h(Az)
    h2a("0x417a")
    """

    static let convertText = """
    # convert
    70 F to C
    25.4 mm to in
    10 kg to lbs
    1 gal to L
    1 MB to bits
    """

    static func text(for key: String?) -> String {
        switch key?.lowercased() {
        case "ee":
            return eeText
        case "prog":
            return progText
        case "convert":
            return convertText
        default:
            return text
        }
    }
}
