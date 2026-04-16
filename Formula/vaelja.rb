class Vaelja < Formula
  desc "Simple, PowerToys-inspired color picker for macOS"
  homepage "https://github.com/0xff4b/homebrew-vaelja"
  url "https://github.com/0xff4b/homebrew-vaelja/archive/refs/tags/v1.0.6.tar.gz"
  sha256 "b4e276b6e07b8cb51be05fc7bd68004bb8f5be1337a442469b0d4066a72b7433"
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
