package org.chisa.intellij

import com.intellij.psi.util.PsiTreeUtil
import com.intellij.testFramework.fixtures.BasePlatformTestCase
import org.chisa.intellij.psi.*
import org.chisa.intellij.settings.ChisaSettings

class ChisaPreludeResolveTest : BasePlatformTestCase() {

    override fun getTestDataPath(): String = "src/test/resources"

    private fun configurePrelude() {
        // Create stdlib files in the test project
        myFixture.addFileToProject(
            "stdlib/string.chisa",
            """
            struct String {
                len: number,
                data: long
            }
            """.trimIndent()
        )
        myFixture.addFileToProject(
            "stdlib/Option.chisa",
            """
            enum Option { Some, None }
            """.trimIndent()
        )
        myFixture.addFileToProject(
            "stdlib/prelude.chisa",
            """
            export { String } from "./string.chisa"
            export { Option } from "./Option.chisa"

            struct Pointer {
                ptr: long
            }

            fn print(s: String): void = 0;
            fn alloc(size: long): long = 0;
            fn read_line(): String = 0;
            """.trimIndent()
        )

        // Point settings to the stdlib directory using VFS URL (works with temp:// in tests)
        val preludeFile = myFixture.findFileInTempDir("stdlib/prelude.chisa")
        assertNotNull("prelude.chisa should exist in temp dir", preludeFile)
        val stdlibDir = preludeFile!!.parent
        ChisaSettings.getInstance(project).stdlibPath = stdlibDir.url
    }

    fun testPreludeFnResolvesWithoutImport() {
        configurePrelude()
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let x = print("hello");
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val printRef = refs.find { it.text == "print" }
        assertNotNull("Should find reference to print", printRef)

        val resolved = printRef!!.reference.resolve()
        assertNotNull("Prelude fn 'print' should resolve without explicit import", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        assertEquals("print", (resolved as ChisaFnDeclaration).name)
    }

    fun testTransitiveExportResolvesViaPrelude() {
        configurePrelude()
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let s: String;
            """.trimIndent()
        )

        val typeRef = PsiTreeUtil.findChildOfType(file, ChisaTypeReferenceElement::class.java)
        assertNotNull("Should find type reference to String", typeRef)

        val resolved = typeRef!!.reference.resolve()
        assertNotNull("Transitive export 'String' should resolve via prelude", resolved)
        assertInstanceOf(resolved, ChisaStructDeclaration::class.java)
        assertEquals("String", (resolved as ChisaStructDeclaration).name)
    }

    fun testTransitiveExportOptionResolvesViaPrelude() {
        configurePrelude()
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let o: Option;
            """.trimIndent()
        )

        val typeRef = PsiTreeUtil.findChildOfType(file, ChisaTypeReferenceElement::class.java)
        assertNotNull("Should find type reference to Option", typeRef)

        val resolved = typeRef!!.reference.resolve()
        assertNotNull("Transitive export 'Option' should resolve via prelude", resolved)
        assertInstanceOf(resolved, ChisaEnumDeclaration::class.java)
        assertEquals("Option", (resolved as ChisaEnumDeclaration).name)
    }

    fun testCompletionIncludesPreludeSymbols() {
        configurePrelude()
        myFixture.configureByText(
            "main.chisa",
            """
            let x = pr<caret>
            """.trimIndent()
        )
        val lookups = myFixture.completeBasic()
        assertNotNull("Completion should return results", lookups)
        val names = lookups.map { it.lookupString }
        assertTrue("Should contain 'print' from prelude, got: $names", names.contains("print"))
    }

    fun testLocalDeclarationShadowsPrelude() {
        configurePrelude()
        val file = myFixture.configureByText(
            "main.chisa",
            """
            fn print(n: number): void = 0;
            let x = print(42);
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val printRef = refs.find { it.text == "print" }
        assertNotNull("Should find reference to print", printRef)

        val resolved = printRef!!.reference.resolve()
        assertNotNull("print should resolve", resolved)
        assertInstanceOf(resolved, ChisaFnDeclaration::class.java)
        // The resolved element should be in main.chisa, not in prelude
        assertEquals("main.chisa", resolved!!.containingFile.name)
    }

    fun testNoPreludeWhenStdlibPathUnconfigured() {
        // Do NOT call configurePrelude() — stdlibPath remains empty
        val file = myFixture.configureByText(
            "main.chisa",
            """
            let x = print("hello");
            """.trimIndent()
        )

        val refs = PsiTreeUtil.findChildrenOfType(file, ChisaReferenceExpression::class.java)
        val printRef = refs.find { it.text == "print" }
        assertNotNull("Should find reference to print", printRef)

        val resolved = printRef!!.reference.resolve()
        assertNull("print should NOT resolve when stdlibPath is unconfigured", resolved)
    }
}
