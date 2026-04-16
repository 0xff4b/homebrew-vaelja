class Vaelja < Formula
  desc "Simple, PowerToys-inspired color picker for macOS"
  homepage "https://github.com/0xff4b/homebrew-vaelja"
  url "https://github.com/0xff4b/homebrew-vaelja/archive/refs/tags/v1.0.3.tar.gz"
  sha256 "1544ee80f10f7d520ff41c588b1726ea5d80f944ea2e69797eea71a36b187317"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "make", "install", "PREFIX=#{bin}"
  end

  def caveats
    <<~EOS
      vaelja runs as a menu bar app. Launch it with:
        vaelja &
      Or add it to Login Items via its own menu.
    EOS
  end

  test do
    assert_predicate bin/"vaelja", :exist?
  end
end
