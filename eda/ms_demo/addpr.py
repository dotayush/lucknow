import pya
ly = pya.Layout(); ly.read(src)
top = ly.top_cell()
bb = top.bbox()
li = ly.layer(235, 4)               # sky130 prBoundary.boundary
top.shapes(li).insert(pya.Box(bb))
ly.write(dst)
print("top", top.name, "bbox um", top.dbbox(), "-> prBoundary 235/4 added")
