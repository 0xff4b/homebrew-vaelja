class Vaelja < Formula
  desc "Simple, PowerToys-inspired color picker for macOS"
  homepage "https://github.com/0xff4b/vaelja"
  url "https://github.com/0xff4b/vaelja/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "d5558cd419c8d46bdc958064cb97f963d1ea793866414c025906ec15033512ed"
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
