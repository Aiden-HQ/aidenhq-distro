// Run inside an OLD release's kernel checkout (copied to its kernel/src by upgrade.sh): the pin that release's own updater
// commits to move an instance to a newer release, minus the network checks. Writes the pinned instance.yaml.
//   node kernel/src/pin-as-installed.ts <instance.yaml> <new release file> <release> <distro sha>
import { readFileSync, writeFileSync } from "node:fs";
import YAML from "yaml";
import { resolveRelease } from "../../scripts/compiler/release.ts";
import { followed, pinText } from "./updates.ts";

const [inst, relFile, name, sha] = process.argv.slice(2) as [string, string, string, string];
const text = readFileSync(inst, "utf8");
const file = JSON.parse(readFileSync(relFile, "utf8"));
if (!followed(YAML.parse(text))) throw new Error("the old updater doesn't see this instance as following a release");
const next = pinText(text, file, name, sha);
resolveRelease(file, YAML.parse(next));
writeFileSync(inst, next);
console.log(`the installed updater pinned ${name} (product: ${file.kernel})`);
