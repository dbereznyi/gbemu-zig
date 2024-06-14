from bs4 import BeautifulSoup

with open("table.html") as f:
    html = f.read()

soup = BeautifulSoup(html, 'html.parser')

def get_size(opcode):
    if opcode == 0xcb:
        return 2

    td = soup.find(id="op-{:02x}".format(opcode))
    if not td:
        return None
    span = td.find(class_="bytes")
    if not span:
        return None
    return int(span.contents[0])

def get_cycles(opcode):
    if opcode == 0xcb:
        return 2

    td = soup.find(id="op-{:02x}".format(opcode))
    if not td:
        return None
    span = td.find(class_="cycles")
    if not span:
        return None
    cycles = span.contents[0]
    if "/" in cycles:
        return (int(cycles.split("/")[0]) // 4, int(cycles.split("/")[1]) // 4)
    else:
        return int(cycles) // 4


def print_size():
    xs = []

    for opcode in range(0, 256):
        size = get_size(opcode)
        if not size:
            continue

        xs.append("0x{:02x} => {}, ".format(opcode, size))

    i = 0
    while i < 256:
        print("".join(xs[i:i+6]))
        i += 6

def print_cycles():
    xs = []
    for opcode in range(0, 256):
        cycles = get_cycles(opcode)
        if not cycles:
            continue

        if type(cycles) == type((1, 2)):
            (x, y) = cycles
            hoge = "if (cond) {} else {}".format(x, y)
        else:
            hoge = cycles
        xs.append("0x{:02x} => {}, ".format(opcode, hoge))

    i = 0
    while i < 256:
        print("".join(xs[i:i+6]))
        i += 6

print_cycles()
