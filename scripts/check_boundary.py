import pya

gds_file = globals()["GDS"]

layout = pya.Layout()
layout.read(gds_file)
top = layout.top_cell()

layer = pya.LayerInfo(189, 4)
count = top.shapes(layer).size()

print("Top:", top.name)
print("Boundary shapes on 189/4:", count)
