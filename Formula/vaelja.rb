class Vaelja < Formula
  desc "Simple, PowerToys-inspired color picker for macOS"
  homepage "https://github.com/0xff4b/vaelja"
  url "https://github.com/0xff4b/vaelja/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "40121a3febcfe70e66560fdee997326ba62569d9be27c818fa0c81afecc1b168"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "make", "install", "PREFIX=#{prefix}"
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
