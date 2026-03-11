import re
import pya

def read_lef_size(lef_file):
    with open(lef_file, "r") as f:
        text = f.read()

    m = re.search(r"SIZE\s+([0-9.]+)\s+BY\s+([0-9.]+)\s*;", text)
    if not m:
        raise RuntimeError(f"Could not find SIZE in LEF: {lef_file}")

    return float(m.group(1)), float(m.group(2))

def get_var(name):
    if name in globals():
        return globals()[name]
    raise RuntimeError(f"Missing parameter: {name}")

def main():
    gds_file = get_var("GDS")
    lef_file = get_var("LEF")
    out_file = get_var("OUT")

    width_um, height_um = read_lef_size(lef_file)

    layout = pya.Layout()
    layout.read(gds_file)
    top = layout.top_cell()

    boundary_layer = layout.layer(pya.LayerInfo(189, 4))

    dbu = layout.dbu
    x2 = int(round(width_um / dbu))
    y2 = int(round(height_um / dbu))

    top.shapes(boundary_layer).clear()
    top.shapes(boundary_layer).insert(pya.Box(0, 0, x2, y2))

    layout.write(out_file)

    print(f"Added top-level prBoundary 189/4 to {top.name}")
    print(f"LEF SIZE: {width_um} um x {height_um} um")
    print(f"DBU: {dbu}")
    print(f"Wrote: {out_file}")

main()
