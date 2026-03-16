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
}
