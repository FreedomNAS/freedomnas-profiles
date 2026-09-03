# Maintainer: FreedomNAS Team <dev@freedomnas.io>
pkgname=freedomnas-profiles
pkgver=4.0.0
pkgrel=1
pkgdesc="FreedomNAS OS Profiles — JSON Translator Layer for universal appliance"
arch=('any')
url="https://codeberg.org/FreedomNAS/freedomnas-profiles"
license=('MPL-2.0')
depends=()
source=("git+https://codeberg.org/FreedomNAS/freedomnas-profiles.git#tag=v${pkgver}")
sha256sums=('SKIP')

package() {
    cd "${srcdir}/${pkgname}"

    # Install profiles to /usr/lib/freedomnas/profiles
    mkdir -p "${pkgdir}/usr/lib/freedomnas/profiles"
    cp -r os init storage network shares users packages \
        "${pkgdir}/usr/lib/freedomnas/profiles/"

    # Install license if exists
    [ -f LICENSE ] && install -Dm 644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
    [ -f README.md ] && install -Dm 644 README.md "${pkgdir}/usr/share/doc/${pkgname}/README.md"
}
