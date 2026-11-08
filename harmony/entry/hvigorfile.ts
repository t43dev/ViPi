import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

// Dữ liệu bộ gõ (../../Resources) được chép vào rawfile/vipi lúc build, không lưu hai lần trong git (như bản Android).
const FILES = [
  'vietnamese-syllables.txt', 'pinyin-words.bin', 'pinyin-abbrev.bin', 'bigram.bin', 's2t.bin',
  'autoswitch-vi.bin', 'autoswitch-en.bin', 'autoswitch-pairs.bin',
];

function vipiData(): HvigorPlugin {
  return {
    pluginId: 'vipiData',
    apply(node: HvigorNode): void {
      const module = node.getNodePath(); // harmony/entry
      const src = process.env.VIPI_RESOURCES || path.resolve(module, '../../Resources');
      const dst = path.resolve(module, 'src/main/resources/rawfile/vipi');
      fs.mkdirSync(dst, { recursive: true });
      for (const name of FILES) {
        const from = path.join(src, name);
        const to = path.join(dst, name);
        if (!fs.existsSync(from)) {
          if (fs.existsSync(to)) {
            continue;
          }
          throw new Error(`ViPi data file missing: ${from}`);
        }
        const a = fs.statSync(from);
        if (fs.existsSync(to) && fs.statSync(to).size === a.size && fs.statSync(to).mtimeMs >= a.mtimeMs) {
          continue;
        }
        fs.copyFileSync(from, to);
      }
    }
  };
}

export default {
  system: hapTasks,
  plugins: [vipiData()]
}
