import json
import argparse

# { "module_name": "new_name", ... }
tracker = {}

# get arg from -i
parser = argparse.ArgumentParser(description='Process netlist JSON file.')
parser.add_argument('-i', '--input', type=str, required=True, help='Input netlist JSON file')
parser.add_argument('-o', '--output', type=str, required=True, help='Output netlist JSON file')
args = parser.parse_args()

print(f"[netlistsvg pre-processor] input_file={args.input}, output_file={args.output}")


with open(args.input, 'r') as file:
    netlist_json = json.load(file)

for module in netlist_json['modules']:
    if module.startswith('$paramod'):
        name_arr = str(module).split('\\')
        for i in range(len(name_arr)):
            # edge case: sometimes we might have $paramod$c0c8bca248425b4dc2ebca8335e76389f2b3d090 shit like this.
            # here we want to split at $, for other's this won't produce an split array of more than 1 element
            # but in the edge case it'll. we'll have to eliminate the longer string. join & then treat the
            # entire string as one. ($paramod < 13 so it'll go through).
            lw_split_arr = str(name_arr[i]).split('$')
            for j in range(len(lw_split_arr)):
                if len(lw_split_arr[j]) > 13:
                    lw_split_arr.pop(j)
                    break
            name_arr[i] = '$'.join(lw_split_arr)
            if len(name_arr[i]) > 13 or name_arr[i] == "\\" or name_arr[i] == "":
                # remove
                name_arr.pop(i)
                break

        new_name = '\\'.join(name_arr)
        for i, (_, value) in enumerate(tracker.items()):
            if value == new_name:
                new_name = new_name + '_' + str(len(module))

        tracker[module] = new_name
    else:
        tracker[module] = module

with open(args.input, 'r') as file:
    netlist_str = file.read()

for (old_name, new_name) in tracker.items():
    # replace all instances of keys with values in the netlist_str
    escaped_old = old_name.replace('\\', '\\\\')
    escaped_new = new_name.replace('\\', '\\\\')
    print(f"renaming {escaped_old} to {escaped_new}")
    netlist_str = netlist_str.replace(escaped_old, escaped_new)

with open(args.output, 'w') as file:
    file.write(netlist_str)

print("renaming completed successfully.")
