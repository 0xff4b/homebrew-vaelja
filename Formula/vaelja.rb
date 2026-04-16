class Vaelja < Formula
  desc "Simple, PowerToys-inspired color picker for macOS"
  homepage "https://github.com/0xff4b/homebrew-vaelja"
  url "https://github.com/0xff4b/homebrew-vaelja/archive/refs/tags/v1.0.4.tar.gz"
  sha256 "08dd393c0c3de5aa03842a88520f063de4723991a4667aa98c672996e0c66b49"
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
