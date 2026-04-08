# soluna_examples

A set of demos to show how to use [soluna](https://github.com/cloudwu/soluna).

## Online Demo

<https://yuchanns.github.io/soluna_examples/>

## Run Locally

### 1. Initialize submodules

```bash
git submodule update --init --recursive
```

### 2. Run native examples

Build the native Soluna runtime first:

```bash
cd soluna
luamake -mode release soluna
cd ..
```

Then run any `.game` file:

```bash
SOLUNA_BIN=$(find soluna/bin -name soluna -type f | head -n 1)
"$SOLUNA_BIN" src/bouncing_ball.game
```

Other examples:

```bash
"$SOLUNA_BIN" src/breakout.game
"$SOLUNA_BIN" src/snake.game
"$SOLUNA_BIN" src/space_shooter.game
```

On Linux, the built binary is usually at `soluna/bin/linux/release/soluna`.

### 3. Run the website locally

The website uses the Soluna WebAssembly runtime. Build the web runtime first:

```bash
cd soluna
luamake -mode release -compiler emcc
cd ..
```

Then start the Astro dev server:

```bash
cd website
pnpm install
pnpm run dev
```

Default local URL:

<http://127.0.0.1:4321/>

