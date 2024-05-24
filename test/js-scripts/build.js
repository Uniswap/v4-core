const { build } = require("esbuild");
const { dependencies, peerDependencies } = require("./package.json");

const entryPoints = [
  "getModifyLiquidityResult",
  "getSqrtPriceAtTick",
  "getTickAtSqrtPrice",
];

const sharedConfig = {
  bundle: true,
  minify: false,
};

for (const entryPoint of entryPoints) {
  build({
    entryPoints: [`src/${entryPoint}.ts`],
    ...sharedConfig,
    platform: "node",
    outfile: `dist/${entryPoint}.js`,
  });
}
